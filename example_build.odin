package main

main :: proc() {
	start_parallel()
	for i in 0 ..< 20 {
		if i == 10 {
			run("sleep", "--version")
		} else {
			run("sleep", "2")
		}
	}
	end_parallel()
}

