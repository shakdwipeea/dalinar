#!/usr/bin/env gxi

(import :std/build-script)

(defbuild-script '("foreign"
		   (gxc: "assimp" "-ld-options" "-lassimp")))
