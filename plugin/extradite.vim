" extradite.vim -- a git browser plugin that extends fugitive.vim
" Maintainer: Jezreel Ng <jezreel@gmail.com>
" Version: 1.0
" License: This file is placed in the public domain.

if exists('g:loaded_extradite')
    finish
endif

let g:loaded_extradite = 1

if !exists('g:extradite_width')
    let g:extradite_width = 60
endif

if !exists('g:extradite_resize')
    let g:extradite_resize = 1
endif

if !exists('g:extradite_showhash')
    let g:extradite_showhash = 0
endif

if !exists('g:extradite_diff_split')
    let g:extradite_diff_split = 'belowright split'
endif

autocmd User Fugitive command! -buffer -bang Extradite :execute s:Extradite(<bang>0)

nnoremap <silent> <Plug>ExtraditeClose :<C-U>call <SID>ExtraditeClose()<CR>

autocmd Syntax extradite call s:ExtraditeSyntax()

function! s:Extradite(bang) abort
  " if we are open, close.
  if s:ExtraditeIsActiveInTab()
    call <SID>ExtraditeClose()
    return
  endif

  let path = FugitivePath(@%, '')

  try
    let git_dir = fugitive#repo().dir()
    let template_cmd = ['--no-pager', 'log', '-n100']
    let bufnr = bufnr('')
    let base_file_name = tempname()
    call s:ExtraditeLoadCommitData(a:bang, base_file_name, template_cmd, path)
    let b:base_file_name = base_file_name
    let b:git_dir = git_dir
    let b:extradite_logged_bufnr = bufnr

    if g:extradite_resize
        exe 'vertical resize '.g:extradite_width
    endif

    command! -buffer -bang Extradite :execute s:Extradite(<bang>0)

    " add :echo<CR> in the end to clear command line after closing extradite
    nnoremap <buffer> <silent> q          :<C-U>call <SID>ExtraditeClose()<CR>:echo<CR>
    nnoremap <buffer> <silent> <CR>       :<C-U>exe <SID>ExtraditeJump("edit")<CR>
    nnoremap <buffer> <silent> <C-v>      :<C-U>exe <SID>ExtraditeJump((&splitbelow ? "botright" : "topleft")." vsplit")<CR>
    nnoremap <buffer> <silent> <C-t>      :<C-U>exe <SID>ExtraditeJump("tabedit")<CR>
    nnoremap <buffer> <silent> <nowait> d :<C-U>exe <SID>ExtraditeDiff(0)<CR>
    nnoremap <buffer> <silent> <C-w>d     :<C-U>exe <SID>ExtraditeDiff(2)<CR>
    " hack to make the cursor stay in the same position. putting line= in ExtraditeDiffToggle / removing <C-U>
    " doesn't seem to work
    nnoremap <buffer> <silent> t    :let line=line('.')<cr> :<C-U>exe <SID>ExtraditeDiffToggle()<CR> :exe line<cr>

    "autocmd CursorMoved <buffer>    exe 'setlocal statusline='.escape(b:extradata_list[line(".")-1]['date'], ' ')
    "autocmd CursorMoved <buffer>    exe 'setlocal statusline=' . lightline#statusline(0)
    autocmd BufEnter <buffer>       call s:ExtraditeSyntax()
    autocmd BufLeave <buffer>       hi! link CursorLine NONE
    autocmd BufLeave <buffer>       hi! link Cursor NONE

    " airline overwrites 'statusline' option for this window, request it to be disabled
    let w:airline_disabled = 1

    call s:ExtraditeDiffToggle()
    let t:extradite_bufnr = bufnr('')
    silent doautocmd User Extradite

    return ''
  catch /^extradite:/
    return 'echoerr v:errmsg'
  endtry
endfunction

function! s:ExtraditeLoadCommitData(bang, base_file_name, template_cmd, ...) abort
  if a:0 >= 1
    let path = a:1
  else
    let path = ''
  endif

  let git_cmd = fugitive#repo().git_command()

  " insert literal tabs in the format string because git does not seem to provide an escape code for it
  if (g:extradite_showhash)
    let cmd = a:template_cmd + ['--pretty=format:%h	%an	%d	%s', '--', path]
  else
    let cmd = a:template_cmd + ['--pretty=format:%an	%d	%s', '--', path]
  endif

  let basecmd = escape(call(fugitive#repo().git_command,cmd,fugitive#repo()), '%')
  let extradata_cmd = a:template_cmd + ['--pretty=format:%h	%ad', '--', path]
  let extradata_basecmd = call(fugitive#repo().git_command,extradata_cmd,fugitive#repo())

  let log_file = a:base_file_name.'.extradite'

  " put the commit IDs in a separate file -- the user doesn't have to know
  " exactly what they are
  if &shell =~# 'csh'
    silent! execute '%write !('.basecmd.' > '.log_file.') >& '.a:base_file_name
  else
    silent! execute '%write !'.basecmd.' > '.log_file.' 2> '.a:base_file_name
  endif

  if v:shell_error
    let v:errmsg = 'extradite: '.join(readfile(a:base_file_name),"\n")
    throw v:errmsg
  endif

  let extradata_str = system(extradata_basecmd)
  let extradata = split(extradata_str, '\n')
  let extradata_list = []

  for line in extradata
    let tokens = matchlist(line, '\([^\t]\+\)\t\([^\t]\+\)')
    call add(extradata_list, {'commit': tokens[1], 'date': tokens[2]})
  endfor

  if empty(extradata_list)
    let v:errmsg = 'extradite: no log entries for the current file were found'
    throw v:errmsg
  endif

  if s:ExtraditeIsActiveInTab()
    silent! edit
  else
    if a:bang
      exe 'keepjumps leftabove vnew'
      let t:extradite_switch_back = 0
    else
      exe 'keepjumps enew'
      let t:extradite_switch_back = 1
    endif
  endif

  " There are some hardly predictable results related to 'modeline' option.
  " Instead of just disabling the option also :read file and remove first
  " (empty) line from original buffer instead of :editing the file.
  setlocal nomodeline
  exe 'silent! read' log_file
  0delete

  let b:git_cmd = git_cmd
  let b:extradata_list = extradata_list

  " Some components of the log may have no value. Or may insert whitespace of their own. Remove the repeated
  " whitespace that result from this. Side effect: removes intended whitespace in the commit data.
  setlocal modifiable
  silent! keepjumps %s/\(\s\)\s\+/\1/g
  keepjumps normal! gg
  setlocal nomodified nomodifiable bufhidden=wipe nonumber nowrap foldcolumn=0 nofoldenable filetype=extradite ts=1 cursorline nobuflisted so=0 nolist
endfunction

" Returns the `commit:path` associated with the current line in the Extradite buffer
function! s:ExtraditePath(...) abort
  if exists('a:1')
    let modifier = a:1
  else
    let modifier = ''
  endif

  let url = expand('#' . b:extradite_logged_bufnr . ':p')
  return b:extradata_list[line(".")-1]['commit'].modifier.':'.FugitivePath(url, '')
endfunction

function! ExtraditeCommitDate() abort
  if !s:ExtraditeIsActiveInTab() | return 'Extradite not active' | endif
  return b:extradata_list[line(".")-1]['date']
endfunction

" Closes the file log and returns the selected `commit:path`
function! s:ExtraditeClose() abort
  if !s:ExtraditeIsActiveInTab()
    return
  endif

  let filelog_winnr = bufwinnr(t:extradite_bufnr)
  exe 'keepjumps '.filelog_winnr.'wincmd w'

  let rev = s:ExtraditePath()
  let extradite_logged_bufnr = b:extradite_logged_bufnr

  if exists('b:extradite_simplediff_bufnr') && bufwinnr(b:extradite_simplediff_bufnr) >= 0
    silent exe 'keepjumps bd!' . b:extradite_simplediff_bufnr
  endif

  if t:extradite_switch_back
    exe b:extradite_logged_bufnr.'buffer'
  endif

  if bufexists(t:extradite_bufnr)
    silent exe 'keepjumps bd!' . t:extradite_bufnr
  endif

  let logged_winnr = bufwinnr(extradite_logged_bufnr)
  if logged_winnr >= 0
    exe 'keepjumps '.logged_winnr.'wincmd w'
  endif

  let t:extradite_bufnr = -1
  " enable airline back on close
  let w:airline_disabled = 0

  return rev
endfunction

" Checks whether there is an Extradite buffer opened in the current tab page
function! s:ExtraditeIsActiveInTab() abort
  return exists('t:extradite_bufnr') && t:extradite_bufnr >= 0 && bufexists(t:extradite_bufnr)
endfunction

function! s:ExtraditeJump(cmd) abort
  let rev = s:ExtraditeClose()

  if a:cmd == 'tabedit'
      exe ':Gtabedit '.rev
  else
      exe a:cmd
      exe ':Gedit '.rev
  endif
endfunction

function! s:ExtraditeDiff(type) abort
  let rev = s:ExtraditeClose()

  if a:type == 2
    exe ':tabedit %|Gdiff '.rev
  else
    exe ':Gdiff'.(a:type ? '!' : '').' '.rev
  endif
endfunction

function! s:ExtraditeSyntax() abort
  let b:current_syntax = 'extradite'

  if (g:extradite_showhash)
    syn match ExtraditeLogId "^\(\w\)\+"
    syn match ExtraditeLogName "\t[^\t]\+\t"
    hi def link ExtraditeLogId Comment
  else
    syn match ExtraditeLogName "^[^\t]\+\t"
  endif

  syn match ExtraditeLogTag "(.*)\t"
  hi def link ExtraditeLogName String
  hi def link ExtraditeLogTag Identifier
  hi! link CursorLine           Visual
  " make the cursor less obvious. has no effect on xterm
  hi! link Cursor               Visual
endfunction

function! s:ExtraditeDiffToggle() abort
  if !exists('b:extradite_simplediff_bufnr') || b:extradite_simplediff_bufnr == -1
    augroup extradite
      autocmd CursorMoved <buffer> call s:SimpleFileDiff(b:git_cmd, s:ExtraditePath('~1'), s:ExtraditePath())
      " vim seems to get confused if we jump around buffers during a CursorMoved event. Moving the cursor
      " around periodically helps vim figure out where it should really be.
      autocmd CursorHold <buffer>  normal! lh
    augroup END
  else
    exe "keepjumps bd" b:extradite_simplediff_bufnr
    unlet b:extradite_simplediff_bufnr
    au! extradite
  endif
endfunction

" Does a git diff on a single file and discards the top few lines of extraneous
" information
function! s:SimpleFileDiff(git_cmd,a,b) abort
  call s:SimpleDiff(a:git_cmd,a:a,a:b)
  let win = bufwinnr(b:extradite_simplediff_bufnr)
  exe 'keepjumps '.win.'wincmd w'
  "keepjumps silent normal! gg
  "setlocal modifiable
  "  keepjumps silent normal! gg5dd
  "setlocal nomodifiable
  keepjumps wincmd p

  if exists('*lightline#update_once')
    call lightline#update_once()
  endif
endfunction

" Does a git diff of commits a and b. Will create one simplediff-buffer that is
" unique wrt the buffer that it is invoked from.
function! s:SimpleDiff(git_cmd,a,b) abort
  if !exists('b:extradite_simplediff_bufnr') || b:extradite_simplediff_bufnr == -1
    exec g:extradite_diff_split
    enew!
    " airline causes strange effects related to status line on window change,
    " this doesn't even disable it, but fixes the effects
    let w:airline_disabled = 1
    command! -buffer -bang Extradite :execute s:Extradite(<bang>0)
    nnoremap <buffer> <silent> q    :<C-U>call <SID>ExtraditeClose()<CR>:echo<CR>
    let bufnr = bufnr('')

    keepjumps wincmd p
    let b:extradite_simplediff_bufnr = bufnr
  endif

  let win = bufwinnr(b:extradite_simplediff_bufnr)
  exe 'keepjumps '.win.'wincmd w'

  " check if we have generated this diff already, to reduce unnecessary shell requests
  if exists('b:files') && b:files['a'] == a:a && b:files['b'] == a:b
    keepjumps wincmd p
    return
  endif

  setlocal modifiable

  silent! %delete _
  let diff = system(a:git_cmd.' diff --no-ext-diff '.a:a.' '.a:b)
  silent put = diff
  " delete the first 5 lines with diff command summary
  keepjumps silent normal! gg5dd

  setlocal ft=diff buftype=nofile nomodifiable

  let b:files = { 'a': a:a, 'b': a:b }
  normal! zR
  keepjumps wincmd p
endfunction

" vim:set ft=vim ts=8 sw=2 sts=2 et
