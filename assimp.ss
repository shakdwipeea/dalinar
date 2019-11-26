(import :dalinar/foreign
	:gerbil/gambit
	(for-syntax :std/stxutil))

(export #t)

(begin-ffi (;; enums
	    aiProcess_CalcTangentSpace
	    aiProcess_Triangulate
	    aiProcess_JoinIdenticalVertices
	    aiProcess_SortByPType
	    

	    ;; lambdas
	    aiImportFile
	    aiGetErrorString
	    aiReleaseImport
	    aiExportScene
	    aiGetExportFormatCount
	    aiGetExportFormatDescription

	    aiExportFormatDesc-id)

  (c-declare "#include <assimp/cimport.h>")
  (c-declare "#include <assimp/cexport.h>")
  (c-declare "#include <assimp/scene.h>")
  (c-declare "#include <assimp/postprocess.h>")

  (define-const aiProcess_CalcTangentSpace)
  (define-const aiProcess_Triangulate)
  (define-const aiProcess_JoinIdenticalVertices)
  (define-const aiProcess_SortByPType)
  
  (define-c-struct aiScene)

  (define-c-lambda aiImportFile (char-string int) (pointer aiScene))
  (define-c-lambda aiGetErrorString () char-string)
  (define-c-lambda aiReleaseImport ((pointer aiScene)) void)

  (define-c-lambda aiExportScene ((pointer aiScene) char-string char-string int) int)

  (define-c-struct aiExportFormatDesc ((id . char-string)
				       (description . char-string)
				       (fileExtension . char-string)))
  
  (define-c-lambda aiGetExportFormatCount () int)
  (define-c-lambda aiGetExportFormatDescription (int) (pointer aiExportFormatDesc)))

(define (with-scene-from-file filename f)
  (let (scene #f)
    (dynamic-wind
	(lambda ()
	  (set! scene
	    (aiImportFile filename (bitwise-ior aiProcess_CalcTangentSpace
						aiProcess_Triangulate
						aiProcess_JoinIdenticalVertices
						aiProcess_SortByPType))))
	(lambda ()
	  (if scene
	    (f scene)
	    (error (aiGetErrorString))))
	(lambda ()
	  (aiReleaseImport scene)))))

(define supported-output-formats
  (lambda () (map (lambda (i) (aiExportFormatDesc-id (aiGetExportFormatDescription i)))
	     (iota (aiGetExportFormatCount)))))

(define +gltf-format+ "gltf2")

(define (convert-to-gltf input-filename output-filename)
  (with-scene-from-file input-filename
			(lambda (scene)
			  (aiExportScene scene +gltf-format+ output-filename 0))))