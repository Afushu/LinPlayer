use std::path::Path;

fn main() {
    // 链接 libmpv(libmpv/mpv.lib)
    let manifest = env!("CARGO_MANIFEST_DIR");
    let libdir = Path::new(manifest).join("libmpv");
    println!("cargo:rustc-link-search=native={}", libdir.display());
    println!("cargo:rustc-link-lib=dylib=mpv");

    // 把 libmpv-2.dll 拷到产物目录(target/<profile>/),让 exe 运行时能找到
    if let Ok(out) = std::env::var("OUT_DIR") {
        // OUT_DIR = target/<profile>/build/<pkg>/out  -> 上溯 3 层到 target/<profile>
        if let Some(profile_dir) = Path::new(&out).ancestors().nth(3) {
            let src = libdir.join("libmpv-2.dll");
            let dst = profile_dir.join("libmpv-2.dll");
            let _ = std::fs::copy(&src, &dst);
        }
    }

    tauri_build::build();
}
