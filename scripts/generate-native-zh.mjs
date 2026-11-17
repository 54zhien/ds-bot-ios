import fs from 'node:fs'
import ts from '../mobile/node_modules/typescript/lib/typescript.js'
import { DICTIONARY } from '../ds-bot/src/client/i18n.js'

const source = fs.readFileSync(new URL('../mobile/src/ui/i18n.ts', import.meta.url), 'utf8')
const file = ts.createSourceFile('i18n.ts', source, ts.ScriptTarget.Latest, true)
const mobile = {}
for (const statement of file.statements) {
  if (!ts.isVariableStatement(statement)) continue
  for (const declaration of statement.declarationList.declarations) {
    if (declaration.name.getText(file) !== 'MOBILE_ZH' || !ts.isObjectLiteralExpression(declaration.initializer)) continue
    for (const property of declaration.initializer.properties) {
      if (!ts.isPropertyAssignment(property)) continue
      const key = ts.isStringLiteral(property.name) ? property.name.text : property.name.getText(file)
      if (ts.isStringLiteral(property.initializer)) mobile[key] = property.initializer.text
    }
  }
}
const merged = { ...mobile, ...DICTIONARY.zh }
for (const key of ['New', 'Light', 'Back']) if (key in mobile) merged[key] = mobile[key]
fs.mkdirSync(new URL('../native/Resources/', import.meta.url), { recursive: true })
fs.writeFileSync(new URL('../native/Resources/zh.json', import.meta.url),
  JSON.stringify(Object.fromEntries(Object.entries(merged).sort(([a], [b]) => a.localeCompare(b))), null, 2) + '\n')
