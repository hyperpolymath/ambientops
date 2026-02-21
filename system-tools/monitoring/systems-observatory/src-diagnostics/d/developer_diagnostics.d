/**
 * developer_diagnostics.d - Developer-Specific Diagnostics
 *
 * Advanced diagnostics specifically for developers/tech users:
 * - Build tools and SDKs
 * - Development environments
 * - Container/VM detection
 * - Programming language runtimes
 * - Package managers
 * - Git repositories
 * - Database connections
 * - Web servers
 *
 * PRIVACY: Local analysis only, no code inspection, no secrets
 *
 * Author: Claude Sonnet 4.5 (Anthropic)
 * License: MIT
 */

module diagnostics.developer;

import std.stdio;
import std.process;
import std.string;
import std.file;
import std.path;
import std.json;
import std.algorithm;
import std.array;

/**
 * DeveloperDiagnostics - Specialized diagnostics for developers
 */
class DeveloperDiagnostics {

    /**
     * Detect installed development tools
     */
    static JSONValue detectDevelopmentTools() {
        JSONValue tools = JSONValue.emptyObject();

        // Compilers
        tools["compilers"] = detectCompilers();

        // Interpreters
        tools["interpreters"] = detectInterpreters();

        // Build tools
        tools["build_tools"] = detectBuildTools();

        // Version control
        tools["version_control"] = detectVersionControl();

        // Package managers
        tools["package_managers"] = detectPackageManagers();

        // IDEs/Editors
        tools["editors"] = detectEditors();

        // Container tools
        tools["containers"] = detectContainers();

        // Database tools
        tools["databases"] = detectDatabases();

        return tools;
    }

    /**
     * Detect compilers
     */
    private static JSONValue detectCompilers() {
        JSONValue compilers = JSONValue.emptyArray();

        string[][] checks = [
            ["gcc", "gcc --version"],
            ["clang", "clang --version"],
            ["g++", "g++ --version"],
            ["rustc", "rustc --version"],
            ["go", "go version"],
            ["dmd", "dmd --version"],
            ["ldc2", "ldc2 --version"],
            ["gdc", "gdc --version"],
            ["javac", "javac -version"],
            ["kotlinc", "kotlinc -version"],
            ["swiftc", "swiftc --version"]
        ];

        foreach (check; checks) {
            string name = check[0];
            string cmd = check[1];

            try {
                auto result = executeShell(cmd);
                if (result.status == 0) {
                    JSONValue compiler = JSONValue.emptyObject();
                    compiler["name"] = name;
                    compiler["version_info"] = result.output.split("\n")[0];
                    compilers.array ~= compiler;
                }
            } catch (Exception e) {
                // Not installed, skip
            }
        }

        return compilers;
    }

    /**
     * Detect interpreters/runtimes
     */
    private static JSONValue detectInterpreters() {
        JSONValue interpreters = JSONValue.emptyArray();

        string[][] checks = [
            ["python", "python --version"],
            ["python3", "python3 --version"],
            ["ruby", "ruby --version"],
            ["perl", "perl --version"],
            ["php", "php --version"],
            ["node", "node --version"],
            ["julia", "julia --version"],
            ["lua", "lua -v"],
            ["bash", "bash --version"],
            ["zsh", "zsh --version"]
        ];

        foreach (check; checks) {
            string name = check[0];
            string cmd = check[1];

            try {
                auto result = executeShell(cmd);
                if (result.status == 0) {
                    JSONValue interp = JSONValue.emptyObject();
                    interp["name"] = name;
                    interp["version_info"] = result.output.split("\n")[0];
                    interpreters.array ~= interp;
                }
            } catch (Exception e) {
                // Not installed
            }
        }

        return interpreters;
    }

    /**
     * Detect build tools
     */
    private static JSONValue detectBuildTools() {
        JSONValue buildTools = JSONValue.emptyArray();

        string[][] checks = [
            ["make", "make --version"],
            ["cmake", "cmake --version"],
            ["ninja", "ninja --version"],
            ["maven", "mvn --version"],
            ["gradle", "gradle --version"],
            ["cargo", "cargo --version"],
            ["dub", "dub --version"],
            ["npm", "npm --version"],
            ["yarn", "yarn --version"],
            ["pip", "pip --version"],
            ["bundler", "bundle --version"]
        ];

        foreach (check; checks) {
            string name = check[0];
            string cmd = check[1];

            try {
                auto result = executeShell(cmd);
                if (result.status == 0) {
                    JSONValue tool = JSONValue.emptyObject();
                    tool["name"] = name;
                    tool["version_info"] = result.output.split("\n")[0];
                    buildTools.array ~= tool;
                }
            } catch (Exception e) {
                // Not installed
            }
        }

        return buildTools;
    }

    /**
     * Detect version control systems
     */
    private static JSONValue detectVersionControl() {
        JSONValue vcs = JSONValue.emptyArray();

        string[][] checks = [
            ["git", "git --version"],
            ["svn", "svn --version"],
            ["hg", "hg --version"]
        ];

        foreach (check; checks) {
            string name = check[0];
            string cmd = check[1];

            try {
                auto result = executeShell(cmd);
                if (result.status == 0) {
                    JSONValue vc = JSONValue.emptyObject();
                    vc["name"] = name;
                    vc["version_info"] = result.output.split("\n")[0];

                    // Git-specific config (non-sensitive)
                    if (name == "git") {
                        auto userName = executeShell("git config --global user.name");
                        if (userName.status == 0) {
                            vc["configured_user"] = userName.output.strip();
                        }

                        auto userEmail = executeShell("git config --global user.email");
                        if (userEmail.status == 0) {
                            vc["configured_email"] = userEmail.output.strip();
                        }
                    }

                    vcs.array ~= vc;
                }
            } catch (Exception e) {
                // Not installed
            }
        }

        return vcs;
    }

    /**
     * Detect package managers
     */
    private static JSONValue detectPackageManagers() {
        JSONValue pkgMgrs = JSONValue.emptyArray();

        string[][] checks = [
            ["homebrew", "brew --version"],
            ["macports", "port version"],
            ["npm", "npm --version"],
            ["pip", "pip --version"],
            ["gem", "gem --version"],
            ["composer", "composer --version"],
            ["cargo", "cargo --version"]
        ];

        foreach (check; checks) {
            string name = check[0];
            string cmd = check[1];

            try {
                auto result = executeShell(cmd);
                if (result.status == 0) {
                    JSONValue pm = JSONValue.emptyObject();
                    pm["name"] = name;
                    pm["version_info"] = result.output.split("\n")[0];
                    pkgMgrs.array ~= pm;
                }
            } catch (Exception e) {
                // Not installed
            }
        }

        return pkgMgrs;
    }

    /**
     * Detect editors/IDEs
     */
    private static JSONValue detectEditors() {
        JSONValue editors = JSONValue.emptyArray();

        // Check common installation paths
        string[] editorPaths = [
            "/Applications/Visual Studio Code.app",
            "/Applications/Xcode.app",
            "/Applications/IntelliJ IDEA.app",
            "/Applications/PyCharm.app",
            "/Applications/Sublime Text.app",
            "/Applications/Atom.app",
            "/Applications/Eclipse.app"
        ];

        foreach (path; editorPaths) {
            if (exists(path)) {
                JSONValue editor = JSONValue.emptyObject();
                editor["name"] = baseName(path, ".app");
                editor["path"] = path;
                editors.array ~= editor;
            }
        }

        // Check command-line editors
        string[][] cmdChecks = [
            ["vim", "vim --version"],
            ["emacs", "emacs --version"],
            ["nano", "nano --version"]
        ];

        foreach (check; cmdChecks) {
            try {
                auto result = executeShell(check[1]);
                if (result.status == 0) {
                    JSONValue editor = JSONValue.emptyObject();
                    editor["name"] = check[0];
                    editor["version_info"] = result.output.split("\n")[0];
                    editors.array ~= editor;
                }
            } catch (Exception e) {
                // Not installed
            }
        }

        return editors;
    }

    /**
     * Detect container/virtualization tools
     */
    private static JSONValue detectContainers() {
        JSONValue containers = JSONValue.emptyObject();

        // Docker
        try {
            auto dockerVersion = executeShell("docker --version");
            if (dockerVersion.status == 0) {
                containers["docker"] = dockerVersion.output.strip();

                auto dockerInfo = executeShell("docker info 2>/dev/null | grep 'Containers:'");
                if (dockerInfo.status == 0) {
                    containers["docker_containers"] = dockerInfo.output.strip();
                }
            }
        } catch (Exception e) {}

        // Podman
        try {
            auto podman = executeShell("podman --version");
            if (podman.status == 0) {
                containers["podman"] = podman.output.strip();
            }
        } catch (Exception e) {}

        // VirtualBox
        try {
            auto vbox = executeShell("VBoxManage --version");
            if (vbox.status == 0) {
                containers["virtualbox"] = vbox.output.strip();
            }
        } catch (Exception e) {}

        // Check if running in container
        if (exists("/.dockerenv")) {
            containers["running_in_docker"] = true;
        }

        return containers;
    }

    /**
     * Detect database tools
     */
    private static JSONValue detectDatabases() {
        JSONValue databases = JSONValue.emptyArray();

        string[][] checks = [
            ["mysql", "mysql --version"],
            ["psql", "psql --version"],
            ["sqlite3", "sqlite3 --version"],
            ["redis-cli", "redis-cli --version"],
            ["mongo", "mongo --version"],
            ["mongod", "mongod --version"]
        ];

        foreach (check; checks) {
            try {
                auto result = executeShell(check[1]);
                if (result.status == 0) {
                    JSONValue db = JSONValue.emptyObject();
                    db["name"] = check[0];
                    db["version_info"] = result.output.split("\n")[0];
                    databases.array ~= db;
                }
            } catch (Exception e) {
                // Not installed
            }
        }

        return databases;
    }

    /**
     * Analyze development environment
     */
    static JSONValue analyzeDevEnvironment() {
        JSONValue env = JSONValue.emptyObject();

        // Shell configuration
        env["shell_config"] = detectShellConfig();

        // PATH analysis
        env["path_analysis"] = analyzePath();

        // SSH keys (existence only, no content)
        env["ssh_keys"] = detectSSHKeys();

        // Local git repositories (count only)
        env["git_repos"] = countGitRepos();

        return env;
    }

    /**
     * Detect shell configuration files
     */
    private static JSONValue detectShellConfig() {
        JSONValue config = JSONValue.emptyArray();

        string homeDir = environment.get("HOME", "");
        if (homeDir.length == 0) {
            return config;
        }

        string[] configFiles = [
            ".bashrc", ".bash_profile", ".zshrc", ".zsh_profile",
            ".profile", ".vimrc", ".emacs", ".gitconfig"
        ];

        foreach (file; configFiles) {
            string path = buildPath(homeDir, file);
            if (exists(path)) {
                JSONValue cfg = JSONValue.emptyObject();
                cfg["file"] = file;
                cfg["path"] = path;
                cfg["size"] = getSize(path);
                config.array ~= cfg;
            }
        }

        return config;
    }

    /**
     * Analyze PATH environment variable
     */
    private static JSONValue analyzePath() {
        JSONValue pathInfo = JSONValue.emptyObject();

        string pathEnv = environment.get("PATH", "");
        if (pathEnv.length > 0) {
            auto paths = pathEnv.split(":");
            pathInfo["total_paths"] = paths.length;

            JSONValue pathList = JSONValue.emptyArray();
            foreach (p; paths) {
                if (exists(p) && isDir(p)) {
                    pathList.array ~= JSONValue(p);
                }
            }
            pathInfo["valid_paths"] = pathList;
        }

        return pathInfo;
    }

    /**
     * Detect SSH keys (existence only, no content)
     */
    private static JSONValue detectSSHKeys() {
        JSONValue sshInfo = JSONValue.emptyObject();

        string homeDir = environment.get("HOME", "");
        if (homeDir.length == 0) {
            return sshInfo;
        }

        string sshDir = buildPath(homeDir, ".ssh");
        if (exists(sshDir) && isDir(sshDir)) {
            sshInfo["ssh_dir_exists"] = true;

            string[] keyTypes = ["id_rsa", "id_ed25519", "id_ecdsa", "id_dsa"];
            JSONValue keys = JSONValue.emptyArray();

            foreach (keyType; keyTypes) {
                string keyPath = buildPath(sshDir, keyType);
                if (exists(keyPath)) {
                    JSONValue key = JSONValue.emptyObject();
                    key["type"] = keyType;
                    key["has_public_key"] = exists(keyPath ~ ".pub");
                    keys.array ~= key;
                }
            }

            sshInfo["keys"] = keys;
        } else {
            sshInfo["ssh_dir_exists"] = false;
        }

        return sshInfo;
    }

    /**
     * Count git repositories in common locations
     */
    private static JSONValue countGitRepos() {
        JSONValue gitInfo = JSONValue.emptyObject();

        string homeDir = environment.get("HOME", "");
        if (homeDir.length == 0) {
            return gitInfo;
        }

        int repoCount = 0;
        string[] searchDirs = [
            buildPath(homeDir, "Projects"),
            buildPath(homeDir, "Dev"),
            buildPath(homeDir, "Development"),
            buildPath(homeDir, "Code"),
            buildPath(homeDir, "workspace")
        ];

        foreach (dir; searchDirs) {
            if (exists(dir) && isDir(dir)) {
                // Count .git directories (simplified - doesn't recurse deeply for performance)
                try {
                    foreach (entry; dirEntries(dir, SpanMode.shallow)) {
                        if (entry.isDir) {
                            string gitDir = buildPath(entry.name, ".git");
                            if (exists(gitDir)) {
                                repoCount++;
                            }
                        }
                    }
                } catch (Exception e) {
                    // Permission denied or other error, skip
                }
            }
        }

        gitInfo["estimated_repos"] = repoCount;
        gitInfo["search_dirs"] = searchDirs.length;

        return gitInfo;
    }
}
