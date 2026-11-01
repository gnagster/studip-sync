import json
from pathlib import Path
import unittest
import gzip
import io
import tempfile
from urllib3.response import HTTPResponse
from unittest.mock import MagicMock, patch

from studip_sync import parsers, session
from studip_sync.logins import general

def response(data=None,status=200,text=''):
    result=MagicMock(ok=status<400,status_code=status,text=text)
    result.json.return_value=data
    result.__enter__.return_value=result
    return result

class CompatibilityTests(unittest.TestCase):
    def test_compressed_download_is_decompressed_before_size_check(self):
        s=session.Session(base_url='https://example.org')
        content=b'lecture notes\n'*20
        r=response()
        r.raw=HTTPResponse(body=io.BytesIO(gzip.compress(content)),headers={'Content-Encoding':'gzip'},preload_content=False,decode_content=False)
        s.session.get=MagicMock(return_value=r)
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'notes.txt'
            s.download_file_api('aa',str(target))
            self.assertEqual(target.read_bytes(),content)

    def test_camtasia_nested_player_and_filename_fallback(self):
        self.assertEqual(parsers.extract_media_best_download_link('<iframe src="movie_player.html"></iframe>'),'movie_player.html')
        self.assertEqual(parsers.extract_media_best_download_link('<script>TSC.playerConfiguration.addMediaSrc("movie.mp4");</script>'),'movie.mp4')
        self.assertEqual(parsers.extract_filename_from_headers({'Content-Type':'video/mp4'},'https://example.org/movie.mp4'),'movie.mp4')
        with self.assertRaises(parsers.ParserError):
            parsers.extract_filename_from_headers({'Content-Type':'text/html'},'https://example.org/login')
        s=session.Session(base_url='https://example.org',plugins=MagicMock())
        listing=response(text='list')
        wrapper=response(text='<iframe src="movie_player.html"></iframe>')
        wrapper.url='https://example.org/media/index.html'
        wrapper.headers={'Content-Type':'text/html'}
        player=response(text='<script>TSC.playerConfiguration.addMediaSrc("movie.mp4");</script>')
        player.url='https://example.org/media/movie_player.html'
        player.headers={'Content-Type':'text/html'}
        video=response()
        video.url='https://example.org/media/movie.mp4'
        video.headers={'Content-Type':'video/mp4'}
        video.raw=io.BytesIO(b'video-content')
        s.session.get=MagicMock(side_effect=[listing,wrapper,player,video])
        with tempfile.TemporaryDirectory() as directory, patch.object(session,'parsers',parsers), patch.object(parsers,'extract_media_list',return_value=[{'hash':'aa','type':'direct_download','media_url':'https://example.org/media/index.html'}]):
            s.download_media('bb',directory,'Course')
            self.assertEqual((Path(directory)/'movie-aa.mp4').read_bytes(),b'video-content')
        self.assertEqual(s.session.get.call_args.args[0],'https://example.org/media/movie.mp4')

    def test_course_bootstrap_and_recent_filter(self):
        store={'setGroups':[{'name':'WiSe 2026/27','data':[{'ids':['a']},{'ids':['b','a']}]},{'name':'SoSe 2026','data':[{'ids':['c']}]}],
               'setCourses':{'a':{'name':'One; course'},'b':{'name':'Two / course'},'c':{'name':'Old'}}}
        app={'appPath':'my-courses/MyCourses','vuexStoreData':{'mycourses':store}}
        html='<div data-vue-app><script type="application/json">'+json.dumps(app)+'</script></div>'
        self.assertEqual([c['course_id'] for c in parsers.extract_courses(html,True)],['a','b'])
        self.assertEqual(len(list(parsers.extract_courses(html,False))),3)
        self.assertEqual(list(parsers.extract_courses(html,True))[1]['save_as'],'Two -- course')
        legacy={'groups':store['setGroups'],'courses':store['setCourses']}
        old='<script>MyCoursesData = '+json.dumps(legacy)+';</script>'
        self.assertEqual(list(parsers.extract_courses(old,True))[0]['save_as'],'One; course')

    def test_login_form_selection_and_missing_fields(self):
        html='<form action="/settings"><input name="security_token" value="wrong"></form><form action="/login"><input name="loginname"><input name="password"><input name="security_token" value="correct"><input name="login_ticket" value="ticket"></form>'
        self.assertEqual(general.GeneralLogin.extract_login_data(html),{'action':'/login','params':{'security_token':'correct','login_ticket':'ticket'}})
        with self.assertRaises(general.ParserError):
            general.GeneralLogin.extract_login_data('<form action="/settings"></form>')

    def test_login_checks_real_authentication(self):
        s=MagicMock()
        s.session.get.side_effect=[response(text='<form action="https://example.org/login"><input name="loginname"><input name="password"></form>'),response(text='<a>Veranstaltungen</a><form id="login-form"></form>')]
        s.session.post.return_value=response()
        with self.assertRaises(general.LoginError):
            general.GeneralLogin.login(s,'test','not-a-secret',{})
        self.assertEqual(s.session.post.call_args.kwargs['data']['Login'],'1')
        s.session.get.side_effect=[response(text='<form action="https://example.org/login"><input name="loginname"><input name="password"></form>'),response(text='<button id="header_avatar_image_link"></button>')]
        general.GeneralLogin.login(s,'test','not-a-secret',{})

    def test_pagination_and_origin_validation(self):
        s=session.Session(base_url='https://example.org')
        s.session.get=MagicMock(side_effect=[response({'data':[{'id':'a'}],'links':{'next':'/jsonapi.php/v1/folders?page=2'}}),response({'data':[{'id':'b'}]})])
        self.assertEqual(s._jsonapi_items('folders'),[{'id':'a'},{'id':'b'}])
        s.session.get=MagicMock(return_value=response({'data':[],'links':{'next':'https://elsewhere.invalid/list'}}))
        with self.assertRaises(session.DownloadError): s._jsonapi_items('folders')
        self.assertEqual(s.session.get.call_count,1)
        s.session.get=MagicMock(return_value=response({'data':{},'links':{}}))
        with self.assertRaises(session.DownloadError): s._jsonapi_items('folders')

    def test_file_conversion_and_download_route(self):
        s=session.Session(base_url='https://example.org')
        root={'id':'aa','relationships':{}}
        file={'id':'bb','attributes':{'name':'lecture.pdf','filesize':100,'chdate':'2026-10-28T12:00:00+01:00','is-downloadable':True}}
        readable={'id':'cc','attributes':{'name':'Subfolder','is-readable':True}}
        unreadable={'id':'dd','attributes':{'name':'Private','is-readable':False}}
        s._jsonapi_items=MagicMock(side_effect=[[root],[file],[readable,unreadable]])
        files,folders=s.get_files_index_from_api('ee')
        self.assertEqual(files[0]['size'],100)
        self.assertEqual(files[0]['chdate'],1793185200)
        self.assertEqual(folders,[{'id':'cc','name':'Subfolder'}])
        self.assertEqual(s.url.files_api_download('bb'),'https://example.org/jsonapi.php/v1/file-refs/bb/content')
        s._jsonapi_items=MagicMock(return_value=[file])
        self.assertTrue(s.check_course_new_files('ee',0))
        self.assertFalse(s.check_course_new_files('ee',2000000000))

    def test_permissions_are_not_treated_as_downloads(self):
        s=session.Session(base_url='https://example.org')
        s.session.get=MagicMock(return_value=response(status=403))
        with self.assertRaises(session.MissingPermissionFolderError): s._jsonapi_items('folders/aa/file-refs')
        with self.assertRaises(session.MissingFeatureError): s._jsonapi_items('courses/aa/file-refs')

if __name__=='__main__': unittest.main()
