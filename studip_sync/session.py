import os
import shutil
import time
import urllib.parse
import json
from datetime import datetime

import requests

from studip_sync import parsers
from studip_sync.constants import URL_BASEURL_DEFAULT, AUTHENTICATION_TYPES
from studip_sync.parsers import ParserError
from studip_sync.plugins.plugin_list import PluginList


class SessionError(Exception):
    pass


class FileError(Exception):
    pass


class MissingFeatureError(Exception):
    pass


class MissingPermissionFolderError(Exception):
    pass


class DownloadError(SessionError):
    pass


class URL(object):
    def __init__(self, base_url):
        self.base_url = base_url

    def __relative_url(self, rel_url):
        return urllib.parse.urljoin(self.base_url, rel_url)

    def login_page(self):
        return self.__relative_url("")

    def files_main(self):
        return self.__relative_url("dispatch.php/course/files")

    def files_index(self, folder_id):
        return self.__relative_url("dispatch.php/course/files/index/{}".format(folder_id))

    def files_flat(self):
        return self.__relative_url("dispatch.php/course/files/flat")

    def bulk_download(self, folder_id):
        return self.__relative_url("dispatch.php/file/bulk/{}".format(folder_id))

    def studip_main(self):
        return self.__relative_url("dispatch.php/start")

    def courses(self):
        return self.__relative_url("dispatch.php/my_courses")

    def mediacast_list(self):
        return self.__relative_url("plugins.php/mediacastplugin/media/index")

    def files_api_top_folder(self, course_id):
        return self.__relative_url("api.php/course/{}/top_folder".format(course_id))

    def files_api_folder(self, folder_id):
        return self.__relative_url("api.php/folder/{}".format(folder_id))

    def files_api_download(self, file_id):
        return self.__relative_url("jsonapi.php/v1/file-refs/{}/content".format(file_id))


class Session(object):

    def __init__(self, plugins=None, base_url=URL_BASEURL_DEFAULT):
        super(Session, self).__init__()
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": "WeWantFileSync"})
        self.url = URL(base_url)

        if plugins is None:
            self.plugins = PluginList()
        else:
            self.plugins = plugins

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.session.__exit__()

    def set_base_url(self, new_base_url):
        self.url = URL(new_base_url)

    def login(self, auth_type, auth_type_data, username, password):
        auth = AUTHENTICATION_TYPES[auth_type]
        auth.login(self, username, password, auth_type_data)

    def get_courses(self, only_recent_semester=False):
        with self.session.get(self.url.courses()) as response:
            if not response.ok:
                raise SessionError("Failed to get courses")

            return parsers.extract_courses(response.text, only_recent_semester)

    def check_course_new_files(self, course_id, last_sync, use_api=True):
        if use_api:
            files = self._jsonapi_items('courses/{}/file-refs'.format(course_id))
            return any(int(datetime.fromisoformat(f['attributes']['chdate']).timestamp()) > last_sync
                       for f in files)

        params = {"cid": course_id}

        with self.session.get(self.url.files_flat(), params=params) as response:
            if not response.ok:
                if response.status_code == 403 and "Documents" in response.text:
                    raise MissingFeatureError("This course has no files")
                else:
                    raise DownloadError("Cannot access course files_flat page")
            last_edit = parsers.extract_files_flat_last_edit(response.text)

        if last_edit == 0:
            print("\tLast file edit couldn't be detected!")
        else:
            print("\tLast file edit: {}".format(
                time.strftime("%d.%m.%Y %H:%M", time.gmtime(last_edit))))
        return last_edit == 0 or last_edit > last_sync

    def download(self, course_id, workdir, sync_only=None):
        params = {"cid": course_id}

        with self.session.get(self.url.files_main(), params=params) as response:
            if not response.ok:
                raise DownloadError("Cannot access course files page")
            folder_id = parsers.extract_parent_folder_id(response.text)
            csrf_token = parsers.extract_csrf_token(response.text)

        download_url = self.url.bulk_download(folder_id)
        data = {
            "security_token": csrf_token,
            # "parent_folder_id": folder_id,
            "ids[]": sync_only or folder_id,
            "download": 1
        }

        with self.session.post(download_url, params=params, data=data, stream=True) as response:
            if not response.ok:
                raise DownloadError("Cannot download course files")
            path = os.path.join(workdir, course_id)
            with open(path, "wb") as download_file:
                shutil.copyfileobj(response.raw, download_file)
                return path

    def download_file(self, download_url, tempfile):
        with self.session.post(download_url, stream=True) as response:
            if not response.ok:
                raise DownloadError("Cannot download file")

            with open(tempfile, "wb") as file:
                response.raw.decode_content = True
                shutil.copyfileobj(response.raw, file)


    def download_file_api(self, file_id, tempfile):
        download_url = self.url.files_api_download(file_id)
        
        with self.session.get(download_url, stream=True) as response:
            if not response.ok:
                raise DownloadError("Cannot download file (HTTP {})".format(response.status_code))

            with open(tempfile, "wb") as file:
                response.raw.decode_content = True
                shutil.copyfileobj(response.raw, file)

    def get_files_index(self, course_id, folder_id=None):
        params = {"cid": course_id}

        if folder_id:
            url = self.url.files_index(folder_id)
        else:
            url = self.url.files_main()

        with self.session.get(url, params=params) as response:
            if not response.ok:
                if response.status_code == 403 and "Documents" in response.text:
                    raise MissingFeatureError("This course has no files")
                elif response.status_code == 403 and "Zugriff verweigert" in response.text:
                    raise MissingPermissionFolderError(
                        "You are missing the required pemissions to view this folder")
                else:
                    raise DownloadError("Cannot access course files/files_index page")
            return parsers.extract_files_index_data(response.text)

    def _jsonapi_items(self, path):
        url = urllib.parse.urljoin(self.url.base_url + '/', 'jsonapi.php/v1/' + path)
        items = []
        seen = set()
        while url:
            if urllib.parse.urlsplit(url)[:2] != urllib.parse.urlsplit(self.url.base_url)[:2] or url in seen:
                raise DownloadError('Invalid JSON-API pagination link')
            seen.add(url)
            with self.session.get(url, timeout=60) as response:
                if response.status_code == 403:
                    if path.startswith('courses/'):
                        raise MissingFeatureError('Course file area is unavailable')
                    raise MissingPermissionFolderError('Folder is not readable')
                if not response.ok:
                    raise DownloadError('JSON-API request failed (HTTP {})'.format(response.status_code))
                try:
                    data = response.json()
                    if not isinstance(data['data'], list):
                        raise ValueError('Expected a resource list')
                    items.extend(data['data'])
                    next_page = data.get('links', {}).get('next')
                    url = urllib.parse.urljoin(url, next_page) if next_page else None
                except (ValueError, KeyError, TypeError) as error:
                    raise DownloadError('Invalid JSON-API response') from error
        return items

    def get_files_index_from_api(self, course_id, folder_id=None):
        if folder_id is None:
            folders = self._jsonapi_items('courses/{}/folders'.format(course_id))
            roots = [f for f in folders if not f.get('relationships', {}).get('parent', {}).get('data')]
            if not folders:
                return [], []
            if len(roots) != 1:
                raise DownloadError('Could not identify the course root folder')
            folder_id = roots[0]['id']

        files = self._jsonapi_items('folders/{}/file-refs'.format(folder_id))
        folders = self._jsonapi_items('folders/{}/folders'.format(folder_id))
        return ([{
            'id': f['id'],
            'name': f['attributes']['name'],
            'size': f['attributes']['filesize'],
            'chdate': int(datetime.fromisoformat(f['attributes']['chdate']).timestamp()),
            'is_downloadable': f['attributes']['is-downloadable'],
        } for f in files], [{
            'id': f['id'], 'name': f['attributes']['name'],
        } for f in folders if f['attributes']['is-readable']])

    def download_media(self, course_id, media_workdir, course_save_as):
        params = {"cid": course_id}

        mediacast_list_url = self.url.mediacast_list()

        with self.session.get(mediacast_list_url, params=params) as response:
            if not response.ok:
                if response.status_code == 500 and "not found" in response.text:
                    raise MissingFeatureError("This course has no media")
                else:
                    raise DownloadError("Cannot access mediacast list page")

            media_files = parsers.extract_media_list(response.text)

        os.makedirs(media_workdir, exist_ok=True)

        workdir_files = os.listdir(media_workdir)

        print("\tFound {} media files".format(len(media_files)))

        for media_file in media_files:
            media_hash = media_file["hash"]
            media_type = media_file["type"]
            media_player_url_relative = media_file["media_url"]
            media_player_url = urllib.parse.urljoin(mediacast_list_url,
                                                       media_player_url_relative)

            # files are saved as "{filename}-{hash}.{extension}"
            # older version might have used the format "{hash}-{filename}.{extension}"

            found_existing_file = False

            for workdir_filename in workdir_files:
                workdir_filename_split = workdir_filename.split("-")

                if workdir_filename_split[0] == media_hash or \
                        workdir_filename_split[-1].split(".")[0] == media_hash:
                    found_existing_file = True
                    break

            # Skip this file if it already exists
            if found_existing_file:
                continue

            print("\t\tDownloading " + media_hash)

            if media_type == "player":
                with self.session.get(media_player_url) as response:
                    if not response.ok:
                        raise DownloadError("Cannot access media file page: " + media_hash)

                    download_media_url_relative = parsers.extract_media_best_download_link(
                        response.text)

                    download_media_url = urllib.parse.urljoin(media_player_url,
                                                                 download_media_url_relative)
            elif media_type == "direct_download":
                download_media_url = media_player_url
            else:
                raise ParserError("media_type is not a valid type")

            for attempt in range(4):
                response = self.session.get(download_media_url, stream=True, timeout=60)
                if not response.ok or 'text/html' not in response.headers.get('Content-Type', ''):
                    break
                with response:
                    link = parsers.extract_media_best_download_link(response.text)
                    download_media_url = urllib.parse.urljoin(response.url, link)
                    if urllib.parse.urlsplit(download_media_url).scheme not in ('https', 'http'):
                        raise DownloadError('Invalid media download URL')
            else:
                raise DownloadError('Too many nested media player pages')

            with response:
                if not response.ok:
                    print("\t\tCannot download media file: " + str(response))
                    continue

                media_filename = parsers.extract_filename_from_headers(response.headers, response.url)
                if os.path.basename(media_filename) != media_filename or media_filename in ('', '.', '..'):
                    raise DownloadError('Invalid media filename')

                media_filename_split = media_filename.split(".")
                media_filename_extension = media_filename_split.pop()
                media_filename_name = ".".join(media_filename_split)

                filename = media_filename_name + "-" + media_hash + "." + media_filename_extension

                filepath = os.path.join(media_workdir, filename)

                if os.path.exists(filepath):
                    raise FileError(
                        "Cannot access filepath since file already exists: " + filepath)

                try:
                    with open(filepath, "wb") as download_file:
                        response.raw.decode_content = True
                        shutil.copyfileobj(response.raw, download_file)
                except OSError as e:
                    os.remove(filepath)
                    raise e

                self.plugins.hook("hook_file_download_successful", media_filename, course_save_as,
                                  filepath)
