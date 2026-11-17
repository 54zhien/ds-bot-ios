import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
const dependency = resolve(root, 'mobile/node_modules/deep-view')
const packageInfo = JSON.parse(readFileSync(resolve(dependency, 'package.json'), 'utf8'))
if (packageInfo.version !== '0.1.0') throw new Error(`Review deep-view ${packageInfo.version} before updating the native formula resource`)

const source = readFileSync(resolve(dependency, 'src/core/formula.js'), 'utf8')
const script = `// Generated from deep-view 0.1.0 src/core/formula.js (Apache-2.0).
// Regenerate with node scripts/generate-native-formula.mjs after installing mobile dependencies.
${source.replace(/^export /gm, '')}

function dsbotFormula(source, inputObject, letObject) {
  const inputs = new Map(Object.entries(inputObject || {}))
  const lets = new Map()
  for (const [name, raw] of Object.entries(letObject || {})) {
    const expression = raw && typeof raw === 'object' && '=' in raw ? String(raw['=']) : String(raw)
    const compiled = compileFormula(expression)
    if (!('error' in compiled)) lets.set(name, compiled.tree)
  }
  const compiled = compileFormula(source)
  if ('error' in compiled) return compiled
  return evaluate(compiled.tree, createScope(inputs, lets))
}
`

writeFileSync(resolve(root, 'native/Resources/deep-view-formula.js'), script)
writeFileSync(resolve(root, 'native/Resources/deep-view-LICENSE.txt'), readFileSync(resolve(dependency, 'LICENSE')))
