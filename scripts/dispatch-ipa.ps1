<#
dispatch-ipa.ps1 - dispatch the native IPA job and survive runner starvation.

The macos-26 pool sometimes assigns no runner at all. The queued ipa job is
reaped after 15m01s: the job records conclusion=cancelled, steps=0 and
runner_id=0, while the run itself concludes failure. A human re-dispatch works
immediately, so this script makes that one retry automatic - and only that one.

The three-way discriminator is the whole value of this script, so it lives in
two isolated functions and nowhere else:

  Get-RunEvidence  - one run id in, every raw field the verdict needs out. I/O
                     only, no interpretation.
  Resolve-Verdict  - evidence in, verdict out. Pure, no I/O, testable alone.

  starved          run=failure + ipa job=cancelled + steps=0 + no runner
  genuine failure  run=failure + anything else (steps were executed - a red
                   build stays red, retrying it burns 15 minutes per attempt)
  cancelled        run=cancelled (a human stopped it, or a newer push of the
                   same group took it down - never retried)

Usage:
  scripts/dispatch-ipa.ps1                          dispatch, poll, retry starved, close out
  scripts/dispatch-ipa.ps1 -ProbeRunId 44334425742  classify an existing run, no dispatch
  scripts/dispatch-ipa.ps1 -SelfTest                run the synthetic verdict matrix

Closeout (on success only): downloads DS-Bot-ios-native-unsigned, renames the
IPA after its own build info - DS-Bot-<version>-native-<sha>-unsigned.ipa -
cross-checks sha256 against build-info-native.json and the sidecar, then copies
it into the artifacts directory Hermes's forwarding task watches.

Not a lever: switching to macos-15. That image has no Xcode 26, and both jobs
of ios-native.yml fail their Xcode gate on it, so the retry stays on macos-26.
#>
[CmdletBinding()]
param(
    [int]$MaxAttempts = 3,
    [int]$PollSeconds = 30,
    [int]$AttemptTimeoutMinutes = 25,
    [int]$RetryPauseSeconds = 60,
    [string]$XcodeVersion = "26.6",
    [long]$ProbeRunId = 0,
    [long]$AdoptRunId = 0,
    [string]$Destination = "D:\DSBotWorkspace\DS Bot iOS\artifacts",
    [switch]$SelfTest
)

$Repo = "54zhien/ds-bot-ios"
$Workflow = "ios-native.yml"
$IpaJobName = "Unsigned native IPA"
$ArtifactName = "DS-Bot-ios-native-unsigned"

# ---------------------------------------------------------------------------
# Evidence: every raw field the verdict needs, nothing interpreted.
# ---------------------------------------------------------------------------
function Get-RunEvidence {
    param([long]$RunId)

    $run = $null
    $runRaw = gh api "repos/$Repo/actions/runs/$RunId" 2>$null
    if ($LASTEXITCODE -eq 0 -and $runRaw) { $run = $runRaw | ConvertFrom-Json }
    if (-not $run) { return $null }

    $job = $null
    $jobsRaw = gh api "repos/$Repo/actions/runs/$RunId/attempts/$($run.run_attempt)/jobs" 2>$null
    if ($LASTEXITCODE -eq 0 -and $jobsRaw) {
        $job = ($jobsRaw | ConvertFrom-Json).jobs |
            Where-Object { $_.name -eq $IpaJobName } |
            Select-Object -First 1
    }

    $stepsCount = -1
    $failedSteps = @()
    if ($job) {
        $stepsCount = @($job.steps).Count
        $failedSteps = @($job.steps |
            Where-Object { $_.conclusion -eq "failure" } |
            ForEach-Object { $_.name })
    }

    [pscustomobject]@{
        RunId           = $RunId
        RunStatus       = $run.status
        RunConclusion   = if ($run.conclusion) { $run.conclusion } else { "(null)" }
        RunAttempt      = $run.run_attempt
        RunCreated      = $run.created_at
        RunUpdated      = $run.updated_at
        JobFound        = [bool]$job
        JobStatus       = if ($job) { $job.status } else { "(no ipa job in this run)" }
        JobConclusion   = if ($job) { if ($job.conclusion) { $job.conclusion } else { "(null)" } } else { "(none)" }
        StepsCount      = $stepsCount
        RunnerId        = if ($job) { if ($null -ne $job.runner_id) { [long]$job.runner_id } else { 0 } } else { -1 }
        RunnerName      = if ($job) { if ($job.runner_name) { $job.runner_name } else { "(none)" } } else { "(none)" }
        FailedSteps     = $failedSteps
    }
}

# ---------------------------------------------------------------------------
# Verdict: pure. Evidence in, one word out. No branch of this function may
# touch the network, so the whole discriminator is provable offline.
# ---------------------------------------------------------------------------
function Resolve-Verdict {
    param($Evidence)

    if (-not $Evidence)                       { return "NotFound" }
    if ($Evidence.RunStatus -ne "completed")  { return "InProgress" }
    if ($Evidence.RunConclusion -eq "success")   { return "Success" }
    if ($Evidence.RunConclusion -eq "cancelled") { return "Cancelled" }

    # The run concluded failure. The ipa job either never got a runner
    # (starved) or actually executed steps (genuine).
    if ($Evidence.JobFound -and
        $Evidence.JobConclusion -eq "cancelled" -and
        $Evidence.StepsCount -eq 0 -and
        $Evidence.RunnerId -le 0) {
        return "Starved"
    }
    return "GenuineFailure"
}

function Show-Evidence {
    param($Evidence, [string]$Tag)
    "{0} run {1}: run.status={2} run.conclusion={3} attempt={4} | ipa job: found={5} status={6} conclusion={7} steps={8} runner_id={9} runner_name={10} | created={11} updated={12}" -f `
        $Tag, $Evidence.RunId, $Evidence.RunStatus, $Evidence.RunConclusion, $Evidence.RunAttempt,
        $Evidence.JobFound, $Evidence.JobStatus, $Evidence.JobConclusion, $Evidence.StepsCount,
        $Evidence.RunnerId, $Evidence.RunnerName, $Evidence.RunCreated, $Evidence.RunUpdated
}

# ---------------------------------------------------------------------------
# Dispatch, poll, retry the starved ones only, close out on success.
# ---------------------------------------------------------------------------
function Get-DispatchRunIds {
    $raw = gh run list -w $Workflow -b main -L 20 --json databaseId,event 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    return @($raw | ConvertFrom-Json |
        Where-Object { $_.event -eq "workflow_dispatch" } |
        ForEach-Object { [long]$_.databaseId })
}

function Invoke-IpaDispatch {
    # Find the new run by id, not by clock or status. The first seconds of a run
    # report status "requested", which a queued/in_progress filter silently drops -
    # that cost one live dispatch. Comparing local time against GitHub's stamps is
    # no better: it works only until the two clocks drift.
    $before = Get-DispatchRunIds
    # gh prints a confirmation; left in the pipeline it joins the return value and the
    # caller gets an array where it expected one id.
    gh workflow run $Workflow --ref main -f runner=macos-26 -f xcode_version=$XcodeVersion | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "gh workflow run failed" }

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 6
        $fresh = @(Get-DispatchRunIds | Where-Object { $before -notcontains $_ })
        if ($fresh.Count -gt 0) { return [long]($fresh | Select-Object -First 1) }
    }
    throw "dispatched but no new workflow_dispatch run appeared on main within 120s"
}

function Save-IpaArtifact {
    param([long]$RunId, [string]$DestinationRoot)

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ipa-" + $RunId)
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    gh run download $RunId -n $ArtifactName -D $tmp
    if ($LASTEXITCODE -ne 0) { throw "gh run download failed for $ArtifactName" }

    # The artifact keeps the paths it was uploaded with (dist/..., native/Support/...),
    # so every file is found by walking, not by assuming a flat folder.
    $infoFile = Get-ChildItem $tmp -Recurse -Filter "build-info-native.json" | Select-Object -First 1
    $sideFile = Get-ChildItem $tmp -Recurse -Filter "DS-Bot-native-unsigned.sha256" | Select-Object -First 1
    $ipa = Get-ChildItem $tmp -Recurse -Filter *.ipa | Select-Object -First 1
    $ent = Get-ChildItem $tmp -Recurse -Filter "*.entitlements" | Select-Object -First 1
    if (-not $infoFile) { throw "the artifact holds no build-info-native.json" }
    if (-not $ipa) { throw "the artifact holds no .ipa" }

    $info = Get-Content $infoFile.FullName -Raw | ConvertFrom-Json
    $sidecar = if ($sideFile) { ((Get-Content $sideFile.FullName -Raw) -split '\s+')[0] } else { "" }

    $hash = (Get-FileHash $ipa.FullName -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $info.sha256) {
        throw "downloaded IPA hashes to $hash but build-info-native.json says $($info.sha256)"
    }
    if ($hash -ne $sidecar) {
        throw "downloaded IPA hashes to $hash but the sidecar says $sidecar"
    }

    $short = $info.commit.Substring(0, 7)
    $name = "DS-Bot-{0}-native-{1}-unsigned.ipa" -f $info.version, $short
    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    $dest = Join-Path $DestinationRoot $name
    Copy-Item $ipa.FullName $dest -Force

    # The resign kit travels with the package: the entitlements template has to sit
    # next to the IPA, or the next person has to go back to the repo for it.
    $entDest = ""
    if ($ent) {
        $entDest = Join-Path $DestinationRoot (($name -replace '\.ipa$', '') + ".entitlements")
        Copy-Item $ent.FullName $entDest -Force
    }

    "run      : $RunId  https://github.com/$Repo/actions/runs/$RunId"
    "ipa      : $name ($($ipa.Length) bytes)"
    if ($entDest) { "entitlements: $(Split-Path $entDest -Leaf) (aps-environment template for resigning)" }
    "sha256   : $hash (matches build-info-native.json and DS-Bot-native-unsigned.sha256)"
    "saved to : $dest"
}

function Invoke-SelfTest {
    $cases = @(
        @{ label = "success as queued then done"
           ev = @{ RunStatus = "completed"; RunConclusion = "success";  RunAttempt = 1; JobFound = $true;  JobStatus = "completed"; JobConclusion = "success";   StepsCount = 16; RunnerId = 8675309; RunCreated = "t0"; RunUpdated = "t1" }
           want = "Success" },
        @{ label = "starved: reaped at 15m01, no runner, no steps"
           ev = @{ RunStatus = "completed"; RunConclusion = "failure"; RunAttempt = 1; JobFound = $true;  JobStatus = "completed"; JobConclusion = "cancelled"; StepsCount = 0;  RunnerId = 0;        RunCreated = "t0"; RunUpdated = "t1" }
           want = "Starved" },
        @{ label = "genuine failure: steps ran and one is red"
           ev = @{ RunStatus = "completed"; RunConclusion = "failure"; RunAttempt = 1; JobFound = $true;  JobStatus = "completed"; JobConclusion = "failure";  StepsCount = 9;  RunnerId = 424242;   RunCreated = "t0"; RunUpdated = "t1" }
           want = "GenuineFailure" },
        @{ label = "run cancelled: a human or a newer push"
           ev = @{ RunStatus = "completed"; RunConclusion = "cancelled"; RunAttempt = 1; JobFound = $true; JobStatus = "completed"; JobConclusion = "cancelled"; StepsCount = 3;  RunnerId = 999;       RunCreated = "t0"; RunUpdated = "t1" }
           want = "Cancelled" },
        @{ label = "still running"
           ev = @{ RunStatus = "in_progress"; RunConclusion = "(null)"; RunAttempt = 1; JobFound = $true;  JobStatus = "queued";    JobConclusion = "(null)";   StepsCount = 0;  RunnerId = 0;        RunCreated = "t0"; RunUpdated = "t1" }
           want = "InProgress" },
        @{ label = "failure with no ipa job at all is not starved"
           ev = @{ RunStatus = "completed"; RunConclusion = "failure"; RunAttempt = 1; JobFound = $false; JobStatus = "(none)";    JobConclusion = "(none)";   StepsCount = -1; RunnerId = -1;       RunCreated = "t0"; RunUpdated = "t1" }
           want = "GenuineFailure" }
    )
    $ok = 0
    foreach ($c in $cases) {
        $ev = [pscustomobject]$c.ev
        $got = Resolve-Verdict $ev
        $good = ($got -eq $c.want)
        if ($good) { $ok++ }
        "{0,-45} steps={1,-3} runner_id={2,-8} job={3,-9} run={4,-10} -> {5}{6}" -f `
            $c.label, $ev.StepsCount, $ev.RunnerId, $ev.JobConclusion, $ev.RunConclusion, $got,
            $(if ($good) { "" } else { "  MISMATCH (want $($c.want))" })
    }
    "self-test: $ok of $($cases.Count) as expected"
    if ($ok -ne $cases.Count) { exit 1 }
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
if ($SelfTest) { Invoke-SelfTest; exit 0 }

if ($ProbeRunId) {
    "probe mode: classifying run $ProbeRunId, no dispatch happens"
    $ev = Get-RunEvidence $ProbeRunId
    if (-not $ev) { "::error::run $ProbeRunId not found"; exit 1 }
    Show-Evidence $ev "[verdict]"
    $verdict = Resolve-Verdict $ev
    "verdict  : $verdict"
    if ($verdict -eq "GenuineFailure" -and $ev.FailedSteps.Count -gt 0) {
        "red steps: " + ($ev.FailedSteps -join ", ")
    }
    if ($verdict -eq "Success" -and $PSBoundParameters.ContainsKey("Destination")) {
        ""
        "probe closeout (explicit -Destination given):"
        Save-IpaArtifact $ProbeRunId $Destination
    }
    exit $(if ($verdict -eq "Success") { 0 } else { 1 })
}

# Real run: dispatch, poll, retry the starved ones, close out.
$script:PollCount = 0
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    if ($attempt -eq 1 -and $AdoptRunId) {
        $runId = $AdoptRunId
        "attempt 1/$MaxAttempts : adopting run $runId (dispatched earlier; no new dispatch)"
    }
    elseif ($attempt -eq 1) {
        "dispatching ios-native.yml (budget: $MaxAttempts attempts, retrying starvation only)..."
        $runId = [long](Invoke-IpaDispatch | Select-Object -Last 1)
        "attempt 1/$MaxAttempts : run $runId"
    }
    else {
        "attempt $attempt/$MaxAttempts : STARVATION retry - the previous run was reaped with no runner assigned (15m01, steps=0); this is not a retry of a red build"
        Start-Sleep -Seconds $RetryPauseSeconds
        $runId = [long](Invoke-IpaDispatch | Select-Object -Last 1)
        "attempt $attempt/$MaxAttempts : new run $runId"
    }

    $deadline = [DateTimeOffset]::UtcNow.AddMinutes($AttemptTimeoutMinutes)
    while ($true) {
        $ev = Get-RunEvidence $runId
        $verdict = Resolve-Verdict $ev
        $script:PollCount++
        if ($ev) { Show-Evidence $ev ("[poll {0}]" -f $script:PollCount) }

        if ($verdict -eq "Success") {
            ""
            "verdict  : SUCCESS - closing out"
            Save-IpaArtifact $runId $Destination
            exit 0
        }
        if ($verdict -eq "Starved") {
            "verdict  : STARVED - the platform reaped the queued job without a runner"
            break
        }
        if ($verdict -eq "GenuineFailure") {
            "verdict  : GENUINE FAILURE - steps were executed and one is red; a retry would burn 15 minutes to learn the same thing"
            if ($ev.FailedSteps.Count -gt 0) { "red steps: " + ($ev.FailedSteps -join ", ") }
            exit 1
        }
        if ($verdict -eq "Cancelled") {
            "verdict  : CANCELLED - a human or a newer run stopped it; not retrying"
            exit 1
        }
        if ($verdict -eq "NotFound") {
            "::error::run $runId vanished from the API"; exit 1
        }
        # InProgress
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            "verdict  : STALLED - no conclusion within $AttemptTimeoutMinutes minutes (starvation resolves at 15m01, so this run holds a runner); leaving it alone, not retrying"
            exit 1
        }
        Start-Sleep -Seconds $PollSeconds
    }
}

"all $MaxAttempts attempts starved: the macos-26 pool is dry right now; try again later"
exit 1
