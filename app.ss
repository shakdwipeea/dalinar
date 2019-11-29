(import :dalinar/assimp)

(export main)

(def (main)
  (convert-to-gltf "models/interior_living_room.obj" "models/interior.gltf"))