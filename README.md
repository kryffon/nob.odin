# nob.odin

Very much inspired by [tsoding/nob.h](https://github.com/tsoding/nob.h) and jai's `first.jai`.

### Usage

- ```
  wget https://raw.githubusercontent.com/kryffon/nob.odin/refs/heads/main/nob.odin
  ```
- ```
  USAGE: odin run . -- [OPTIONS]
  OPTIONS:
  	- b: executes only build commands
  	- r: executes only run commands
  	- d: executes only debug commands
  ```
  By default it executes build and run commands only. There is no difference between build, run and debug commands. They simply help in grouping commands for deciding which group should be executed.

- Recommended directory structure:
  ```
  project_dir
  	├ src          // all source code
  	├ nob.odin
  	└ build.odin   // your build script
  ```

- Example `build.odin`
  ```odin
  package main

  main :: proc() {
  	watch(outfile = "./my_program", path = "./src", filetype = ".odin")
  	build("odin", "build", "./src", "-out:my_program")
  	run("./my_program")
  }
  ```

- Now simply do
  ```bash
  odin run .
  odin run . -- r
  odin run . -- bd
  odin run . -- b r
  ```

- For parallel execution, enclose commands between `start_parallel()` and `end_parallel()`
  ```odin
  start_parallel()
  for in_path in shader_files {
      out_path := fmt.tprintf("%s.spv", in_path)
      build("glslc", in_path, "-o", out_path)
  }
  end_parallel()
  ```

- Use fork variants for each command to run programs that use alt-mode in terminal.
  ```odin
  debug_fork("nnd", "./my_program")
  ```
