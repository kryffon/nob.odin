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
  By default it executes build and run commands.

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
