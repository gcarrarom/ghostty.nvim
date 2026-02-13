if exists("b:current_syntax")
  finish
endif

" Full-line comments
syn match ghosttyComment /^\s*#.*$/

" key = value
syn match ghosttyKey /^\s*[^#=\s][^=]*\ze\s*=/
syn match ghosttyEquals /=/

" Value part (after '='), excluding inline comment
syn match ghosttyValue /=\s*\zs.\{-}\ze\(\s\+#.*\)\?$/

" Inline comments that come after whitespace
syn match ghosttyInlineComment /\s\+#.*$/

" Quoted strings
syn region ghosttyString start=/"/ skip=/\\"/ end=/"/

" Paths
syn match ghosttyPath /\~\/[A-Za-z0-9_\/\.\-]\+/
syn match ghosttyPath /\/[A-Za-z0-9_\/\.\-]\+/

hi def link ghosttyComment Comment
hi def link ghosttyInlineComment Comment
hi def link ghosttyKey Identifier
hi def link ghosttyEquals Operator
hi def link ghosttyValue String
hi def link ghosttyString String
hi def link ghosttyPath Directory

let b:current_syntax = "ghostty"
