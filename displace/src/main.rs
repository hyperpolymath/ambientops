use std::{env, fs};
use std::path::{Path, PathBuf};

fn copy_dir_recursive(source: &Path, destination: &Path) -> Result<(), Box<dyn std::error::Error>> {
    fs::create_dir_all(destination)?;

    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let source_path = entry.path();
        let destination_path = destination.join(entry.file_name());

        if file_type.is_file() {
            fs::copy(&source_path, &destination_path)?;
        } else if file_type.is_dir() {
            copy_dir_recursive(&source_path, &destination_path)?;
        }
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();

    if args.len() != 3 {
        eprintln!("Usage: {} <SOURCE> <DESTINATION>", args[0]);
        std::process::exit(1);
    }

    let source_path = PathBuf::from(&args[1]);
    let destination_path = PathBuf::from(&args[2]);

    println!("Attempting to copy from {:?} to {:?}", source_path, destination_path);

    if source_path.is_file() {
        // If source is a file, copy it directly
        fs::copy(&source_path, &destination_path)?;
        println!("Successfully copied file from {:?} to {:?}", source_path, destination_path);
    } else if source_path.is_dir() {
        // If source is a directory, use recursive copy
        copy_dir_recursive(&source_path, &destination_path)?;
        println!("Successfully copied directory from {:?} to {:?}", source_path, destination_path);
    } else {
        eprintln!("Error: Source path {:?} does not exist or is not a file or directory.", source_path);
        std::process::exit(1);
    }

    Ok(())
}
