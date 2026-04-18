# Qfrun.nvim

![Qfrun](https://github.com/user-attachments/assets/74b9127a-0e87-4e1a-89ce-3510affd7150)

## Installation

```lua
{
  "Kurama622/qfrun.nvim",
  opts = {
    project_config_name = ".env",
    parse_stdout_as_stderr = false,
    -- set language compile options
    -- e.g.
    -- cpp = {
    --   { cmd = "g++ -Wall ${SRC} -o ${TARGET} && ./${TARGET}", desc = "run in qf" },
    --   { cmd = "g++ -Wall ${SRC} -o ${TARGET}", on_done = "./${TARGET}", desc = "run in term mode" },
    --   { cmd = "make", desc = "build by make" },
    -- },
    -- python = "python ${SRC}".
    -- c = "gcc ${SRC} -o ${TARGET}->./${TARGET}", -- <build cmd>-><on_done cmd>
  },
}
```

## Usage

set language compile options in opts or set the project config file (default `.env`)

`.env`:
- `PROJECT_COMPILE_LANGS`: Optional. Analysis of output in multiple languages. Place at the beginning of the `.env` file.
    - e.g.: `PROJECT_COMPILE_LANGS=python,cpp`
- `SRC_DIR`: Optional. When the error message contains an incorrect path, configure it.
- `QF_{language}_COMPILE_COMMAND`


```bash
SRC_DIR=/home/usename/source_code_path
QF_CPP_COMPILE_COMMAND=./build.sh
QF_C_COMPILE_COMMAND=./build.sh->./output
```


```
:QfCompile
:QfReCompile
:QfClose
```

Press `i` in qf window to input the arguments to be executed.

popup_win_opts: (on_done window options)
- relative
- width_ratio
- height_ratio
- border

## Reference

- https://github.com/glepnir/nvim/blob/main/lua/private/compile.lua
