"""Skip Swift extraction only for changes known to belong to docs or the Python CLI."""
import os
import subprocess


def needs_swift_scan(paths):
    def unrelated(path):
        return (path in {"README.md", "Pipfile", "Pipfile.lock", "requirements.txt"}
                or path.startswith("docs/") and path.endswith(".md")
                or path.startswith(("studip_sync/", "tests/")) and path.endswith(".py"))
    return not paths or any(not unrelated(path) for path in paths)


if __name__ == "__main__":
    scan = True
    if os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
        base = os.environ["STUDSYNC_BASE_SHA"]
        changed = subprocess.check_output(["git", "diff", "--name-only", "-z", base, "HEAD"])
        paths = [path.decode("utf-8", errors="surrogateescape") for path in changed.split(b"\0") if path]
        scan = needs_swift_scan(paths)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"scan={str(scan).lower()}\n")
    print("Swift scan required." if scan else "Swift inputs unchanged; only documentation or Python CLI files changed.")
