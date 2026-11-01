import json
import os
import subprocess
from contextlib import contextmanager


class ConfigError(Exception):
    pass


@contextmanager
def open_private_file(path, mode):
    # Restrict existing files before truncation, including macOS ACL read grants.
    with open(path, mode, opener=lambda path, flags: os.open(
            path, flags & ~os.O_TRUNC, 0o600)) as file:
        os.fchmod(file.fileno(), 0o600)
        subprocess.run(['/bin/chmod', '-N', '/dev/fd/{}'.format(file.fileno())],
                       pass_fds=(file.fileno(),), check=True)
        if 'w' in mode:
            file.truncate(0)
        yield file


class JSONConfig(object):
    def __init__(self, config_path=None):
        super(JSONConfig, self).__init__()

        try:
            with open_private_file(config_path, "r") as config_file:
                self.config = json.load(config_file)
        except FileNotFoundError:
            raise ConfigError("Config file missing! Run 'studip-sync --init' to create a new "
                              "config file")

        self._check()

    def _check(self):
        pass

    @staticmethod
    def save_config(path, config):
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        with open_private_file(path, "w") as config_file:
            print("Writing new config to '{}'".format(path))
            json.dump(config, config_file, ensure_ascii=False, indent=4)
