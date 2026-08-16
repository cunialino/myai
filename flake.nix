{
  description = "llama.cpp with Vulkan enabled (RADV/Mesa)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    llama-cpp = {
      url = "github:ggml-org/llama.cpp/b10167";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      llama-cpp,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      aiUtils = pkgs.python3.withPackages (
        ps: with ps; [
          huggingface-hub
          python
        ]
      );
      llamaCppVulkan = llama-cpp.packages.${system}.default.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.vulkan-loader
          pkgs.shaderc
          pkgs.vulkan-headers
        ];

        # We remove amdvlk and rely on Mesa/RADV
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
          pkgs.vulkan-loader
          pkgs.mesa # This provides RADV
        ];
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [
          "-DGGML_VULKAN=1"

          "-DGGML_AVX2=ON"
          "-DGGML_FMA=ON"
          "-DGGML_F16C=ON"

          "-DCMAKE_BUILD_TYPE=Release"

          "-DGGML_VULKAN_MEMORY_DEBUG=OFF"
          "-DGGML_VULKAN_VALIDATE=OFF"
          "-DVulkan_INCLUDE_DIR=${pkgs.vulkan-headers}/include"
          "-DVulkan_LIBRARY=${pkgs.vulkan-loader}/lib/libvulkan.so"
        ];
      });
    in
    {
      defaultPackage.${system} = llamaCppVulkan;

      dockerImage = pkgs.dockerTools.buildImage {
        name = "llama-server-radv";
        tag = "latest";

        copyToRoot = pkgs.buildEnv {
          name = "image-root";
          paths = [
            llamaCppVulkan
            pkgs.vulkan-loader
            pkgs.mesa
          ];
          pathsToLink = [
            "/bin"
            "/lib"
          ];
        };

        config = {
          Env = [
            "VK_ICD_FILENAMES=${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
            "AMD_VULKAN_ICD=RADV"
            "LD_LIBRARY_PATH=/nix/store/*/lib:${pkgs.vulkan-loader}/lib"
          ];
          Cmd = [ "llama-server" ];
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          llamaCppVulkan
          aiUtils
        ];
        shellHook = ''
          export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
          export AMD_VULKAN_ICD=RADV

          echo "[vulkan-env] Switched to RADV/Mesa (AMDVLK is deprecated)"
          echo "[vulkan-env] Driver path: $VK_ICD_FILENAMES"
        '';
      };
    };
}
