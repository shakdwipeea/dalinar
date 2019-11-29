#!/usr/bin/env gxi

(import :std/build-script)

(defbuild-script '("foreign"
		   "test"
		   (gxc: "assimp" "-ld-options" "-lassimp")
		   (exe: "app")))
