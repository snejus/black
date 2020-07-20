" black.vim
" Author: Łukasz Langa, modified by Šarūnas Nejus
" Created: Mon Mar 26 23:27:53 2018 -0700
" Requires: Vim Ver7.0+, isort v5
" Version:  2.0
"
" Documentation:
"   This plugin formats Python files.
"
" History:
"  1.0:
"    - initial version
"  1.1:
"    - restore cursor/window position after formatting

if v:version < 700 || !has('python3')
    echo "This script requires vim7.0+ with Python 3.6 support."
    finish
endif

if exists("g:load_black")
   finish
endif

let g:load_black = "py1.0"
if !exists("g:black_virtualenv")
  if has("nvim")
    let g:black_virtualenv = "~/.local/share/nvim/black"
  else
    let g:black_virtualenv = "~/.vim/black"
  endif
endif
if !exists("g:black_fast")
  let g:black_fast = 0
endif
if !exists("g:black_linelength")
  let g:black_linelength = 88
endif
if !exists("g:black_skip_string_normalization")
  let g:black_skip_string_normalization = 0
endif

python3 << endpython3
import os
import sys
import vim

def _get_python_binary(exec_prefix):
  try:
    default = vim.eval("g:pymode_python").strip()
  except vim.error:
    default = ""
  if default and os.path.exists(default):
    return default
  if sys.platform[:3] == "win":
    return exec_prefix / 'python.exe'
  return exec_prefix / 'bin' / 'python3'

def _get_pip(venv_path):
  if sys.platform[:3] == "win":
    return venv_path / 'Scripts' / 'pip.exe'
  return venv_path / 'bin' / 'pip'

def _get_virtualenv_site_packages(venv_path, pyver):
  if sys.platform[:3] == "win":
    return venv_path / 'Lib' / 'site-packages'
  return venv_path / 'lib' / f'python{pyver[0]}.{pyver[1]}' / 'site-packages'

def _initialize_black_env(upgrade=False):
  pyver = sys.version_info[:2]
  if pyver < (3, 6):
    print("Sorry, Black requires Python 3.6+ to run.")
    return False

  from pathlib import Path
  import subprocess
  import venv
  virtualenv_path = Path(vim.eval("g:black_virtualenv")).expanduser()
  virtualenv_site_packages = str(_get_virtualenv_site_packages(virtualenv_path, pyver))
  first_install = False
  if not virtualenv_path.is_dir():
    print('Please wait, one time setup for Black.')
    _executable = sys.executable
    try:
      sys.executable = str(_get_python_binary(Path(sys.exec_prefix)))
      print(f'Creating a virtualenv in {virtualenv_path}...')
      print('(this path can be customized in .vimrc by setting g:black_virtualenv)')
      venv.create(virtualenv_path, with_pip=True)
    finally:
      sys.executable = _executable
    first_install = True
  if first_install:
    print('Installing Black with pip...')
  if upgrade:
    print('Upgrading Black with pip...')
  if first_install or upgrade:
    subprocess.run([str(_get_pip(virtualenv_path)), 'install', '-U', 'black'], stdout=subprocess.PIPE)
    print('DONE! You are all set, thanks for waiting ✨ 🍰 ✨')
  if first_install:
    print('Pro-tip: to upgrade Black in the future, use the :BlackUpgrade command and restart Vim.\n')
  if virtualenv_site_packages not in sys.path:
    sys.path.append(virtualenv_site_packages)
  return True

if _initialize_black_env():
    import sys
    import time
    from io import StringIO
    from isort import main, api
    import black
    config_overrides = {
        "multi_line_output": 3,
        "include_trailing_comma": True,
        "known_third_party": "model_utils",
        "known_first_party": "interaction,stubs",
    }

def Black():
    code = vim.current.buffer
    filename = code.name
    if not main.is_python_file(filename):
        print("[black / isort] Non-python files aren't supported.")
    else:
        start = time.time()
        line_length = 90
        is_pyi = False
        if filename.endswith(".pyi"):
            line_length = 130
            is_pyi = True
        config_overrides["line_length"] = line_length
        happyisort = None
        try:
            sorted_ = api.sort_code_string("\n".join(code) + "\n", main.Config(**config_overrides))
            code[:] = sorted_.split(sep="\n")
            happyisort = f'[isort] {time.time() - start:.4f}s '
        except Exception as exc:
            raise exc("[isort] unexpectedly failed to isort. You'll have to do it yourself: " + str(exc))

        ### BLACK time
        start = time.time()
        buffer_str = '\n'.join(code) + '\n'
        fast = bool(int(vim.eval("g:black_fast")))
        mode = black.FileMode(
            line_length=line_length,
            string_normalization=not bool(int(vim.eval("g:black_skip_string_normalization"))),
            is_pyi=is_pyi,
        )
        try:
            new_buffer_str = black.format_file_contents(buffer_str, fast=fast, mode=mode)
        except black.NothingChanged:
            print(happyisort + f'[black] {time.time() - start:.4f}s')
        except Exception as exc:
            raise exc("[black] unexpectedly failed to blacken: " + str(exc))
        else:
            current_buffer = vim.current.window.buffer
            cursors = []
            for i, tabpage in enumerate(vim.tabpages):
                if tabpage.valid:
                    for j, window in enumerate(tabpage.windows):
                        if window.valid and window.buffer == current_buffer:
                            cursors.append((i, j, window.cursor))
            vim.current.buffer[:] = new_buffer_str.split('\n')[:-1]
            for i, j, cursor in cursors:
                window = vim.tabpages[i].windows[j]
                try:
                    window.cursor = cursor
                except vim.error:
                    window.cursor = (len(window.buffer), 0)
            print(happyisort + f'[black] {time.time() - start:.4f}s')


def BlackUpgrade():
  _initialize_black_env(upgrade=True)

def BlackVersion():
    print(f'Black, version {black.__version__} on Python {sys.version}.')

endpython3

command! Black :py3 Black()
command! BlackUpgrade :py3 BlackUpgrade()
command! BlackVersion :py3 BlackVersion()
