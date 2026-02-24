import Prism from 'prismjs'
import 'prismjs/themes/prism.css'

/** Syntax-highlight a JavaScript code string. Returns HTML. */
export function highlightJs(code: string): string {
  return Prism.highlight(code, Prism.languages.javascript, 'javascript')
}
