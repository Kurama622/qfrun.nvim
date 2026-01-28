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
    -- cpp = {"g++ -Wall ${SRC} -o ${TARGET} && ./${TARGET}", "make"},
    -- python = "python ${SRC}".
  },
}
```

## Usage

set language compile options in opts or set the project config file (default `.env`)

`.env`:
- `SRC_DIR`: Optional. When the error message contains an incorrect path, configure it.
- `QF_{language}_COMPILE_COMMAND`


```bash
SRC_DIR=/home/<usename>/<path>
QF_CPP_COMPILE_COMMAND=./build.sh
```


```
:QfCompile
:QfReCompile
:QfClose
```

## Reference

- https://github.com/glepnir/nvim/blob/main/lua/private/compile.lua
