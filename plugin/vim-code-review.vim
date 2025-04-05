if (has('nvim') && !has('nvim-0.5')) || (!has('nvim') && v:version < 800) || exists('g:initiated_vim_code_review') || &cp
    finish
endif

let g:initiated_vim_code_review = 1

"==============================================================================
" CONFIGURATION VARIABLES
"==============================================================================

" General settings
let g:code_review_ollama_model = get(g:, 'code_review_ollama_model', '')
let g:code_review_open_router_model = get(g:, 'code_review_open_router_model', '')
let g:code_review_provider = get(g:, 'code_review_provider', '')

"==============================================================================
" UTILITY FUNCTIONS 
"==============================================================================
function! s:get_visual_selection()
    " Why is this not a built-in Vim script function?!
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction

function! s:getStartLineOfSelection()
    " Why is this not a built-in Vim script function?!
    let [line_start, column_start] = getpos("'<")[1:2]
    return line_start
endfunction

"==============================================================================
" FUNCTIONS 
"==============================================================================

:function! s:CodeReview(method, question) range
  :cclose
  :redraw
  :call s:CallCodeReview(a:method, a:question)
:endfunction

:function! s:CallCodeReview(method, question) range
  :let l:selectedText = s:get_visual_selection()
  :let l:startLine = s:getStartLineOfSelection()
  :let l:filename = expand('%')

  :let l:model = ''
  :if g:code_review_provider == 'ollama'
    :let l:model = g:code_review_ollama_model
  :elseif g:code_review_provider == 'open-router'
    :let l:model = g:code_review_open_router_model
  :endif
  
  let l:providerText = ''
  let l:snippet = 0 
  let l:snippetText = ''
  let l:modelText = ''
  let l:questionText = ''

  if a:question != ''
    :let l:questionText = " --question '" . (a:question) . "'"  
  :endif

  :if g:code_review_provider != ''
    :let l:providerText = "--provider " . (g:code_review_provider)
  :endif

  :if l:model
    :let l:modelText = " --model " . (l:model)
  :endif

  
  let l:methodText = " --method " . a:method


  :if !empty(l:selectedText) && len(l:selectedText) > 1
    :let l:snippet = 1
    :let l:snippetText = " --code '" . (l:selectedText) . "' --start " . (l:startLine) . " "
    :echo "Checking selection. Please wait.. (Ctrl-C to cancel)"
  :else
    :echo "Checking file. Please wait.. (Ctrl-C to cancel)"
  :endif

  :let l:cmd = "emurph-code-checker " . l:methodText . " " . l:providerText . " --file " . (l:filename) . " " . l:snippetText . " " . l:questionText . " " . l:modelText 

  :try
     :call AsyncSystemCall(['sh', '-c', l:cmd], function('HandleResult'))


  :catch
    :echo "Error: " . v:exception
  :endtry

  :execute 'normal! y' 
  :exec 'normal! vy'

:endfunction



function! AsyncSystemCall(cmd, callback)
  let l:options = {}
  let l:return_data = {'stdout': [], 'stderr': []}
  
  if has('nvim')
    " Neovim implementation
    function! l:options.on_stdout(job_id, data, event) closure
      if !empty(a:data)
        let l:return_data.stdout += a:data
      endif
    endfunction
    
    function! l:options.on_stderr(job_id, data, event) closure
      if !empty(a:data)
        let l:return_data.stderr += a:data
      endif
    endfunction
    
    function! l:options.on_exit(job_id, exit_code, event) closure
      " Filter out empty lines that Neovim might add
      call filter(l:return_data.stdout, {idx, val -> !empty(val)})
      call filter(l:return_data.stderr, {idx, val -> !empty(val)})
      call a:callback(l:return_data)
    endfunction
    
    let l:job = jobstart(a:cmd, l:options)
  else
    " Vim implementation
    function! l:options.out_cb(channel, message) closure
      let l:return_data.stdout += [a:message]
    endfunction
    
    function! l:options.err_cb(channel, message) closure
      let l:return_data.stderr += [a:message]
    endfunction
    
    function! l:options.close_cb(channel) closure
      call a:callback(l:return_data)
    endfunction
    
    let l:options.mode = 'nl'
    let l:job = job_start(a:cmd, l:options)
  endif
  
  return l:job
endfunction

function! HandleResult(result)
  " echom "STDOUT: " . join(a:result.stdout, "\n")
  " echom "STDERR: " . join(a:result.stderr, "\n")
  :let l:jsonFixes = json_decode(a:result.stdout)
  :try 
      :silent! call setqflist(l:jsonFixes, 'r')
  :catch
    :echo "Error parsing JSON response from server."
  :endtry
  :if len(l:jsonFixes) > 0
    :try
      :copen 
    :catch
      :echo "Error opening quickfix window."
    :endtry
  :endif
endfunction

:command! -range CodeReview '<,'>  call s:CodeReview('review', '')
:command! -range CodeReviewExplain '<,'>  call s:CodeReview('explain', '')
:command! -range -nargs=1 CodeReviewAskQuestion '<,'>  call s:CodeReview('question', <q-args>)
