"""Platform configuration and public-URL checks, without native iOS execution."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import sys
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import urlopen
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import server


class MobileConfigurationTest(unittest.TestCase):
    def test_ios_local_http_exception_is_limited_to_debug(self):
        ios = ROOT.parent / 'map_poc/ios'
        prod = plistlib.loads((ios / 'Runner/Info.plist').read_bytes())
        debug = plistlib.loads((ios / 'Runner/Info-Debug.plist').read_bytes())
        self.assertNotIn('NSAppTransportSecurity', prod)
        self.assertEqual(debug.pop('NSAppTransportSecurity'), {'NSAllowsLocalNetworking': True})
        self.assertIn('NoWave', debug.pop('NSLocalNetworkUsageDescription'))
        self.assertEqual(debug, prod)
        project = (ios / 'Runner.xcodeproj/project.pbxproj').read_text()
        for mode, plist in [('Debug', 'Info-Debug.plist'), ('Profile', 'Info.plist'), ('Release', 'Info.plist')]:
            blocks = re.findall(r'[A-F0-9]{24} /\* ' + mode +
                r' \*/ = \{\n\t\t\tisa = XCBuildConfiguration;(.*?)\n\t\t\};', project, re.S)
            app = [b for b in blocks if re.search(r'^\s*INFOPLIST_FILE\s*=', b, re.M)]
            self.assertEqual(len(app), 1)
            self.assertIn('Runner/' + plist, app[0])
        self.assertIn('FlutterGeneratedPluginSwiftPackage', project)
        self.assertIn('IPHONEOS_DEPLOYMENT_TARGET = 15.0', project)

    def test_android_cleartext_is_debug_only_and_dart_url_is_shared(self):
        app = ROOT.parent / 'map_poc'
        android = '{http://schemas.android.com/apk/res/android}'
        main = ET.parse(app / 'android/app/src/main/AndroidManifest.xml').getroot()
        debug = ET.parse(app / 'android/app/src/debug/AndroidManifest.xml').getroot()
        self.assertEqual(main.find('application').get(android + 'usesCleartextTraffic'), 'false')
        self.assertEqual(debug.find('application').get(android + 'usesCleartextTraffic'), 'true')
        self.assertIn('android.permission.INTERNET', [p.get(android + 'name') for p in main.findall('uses-permission')])
        dart = (app / 'lib/main.dart').read_text()
        self.assertIn("'NOWAVE_STYLE_URL'", dart)
        self.assertNotIn('10.0.2.2', dart)
        self.assertNotIn('Platform.isAndroid', dart)
        self.assertNotIn('ACCESS_FINE_LOCATION', ET.tostring(main).decode())

    def test_public_https_base_is_used_for_style_glyphs_sprites_and_geojson(self):
        config = argparse.Namespace(mbtiles=None, public_url='https://maps.nowave.example/',
            bathymetry_tiles=None, relief_tiles=None, attribution=None, center=None,
            region='cassis')
        httpd = ThreadingHTTPServer(('127.0.0.1', 0), server.handler_class(config))
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            with urlopen(f'http://127.0.0.1:{httpd.server_port}/style.json') as response:
                style = json.load(response)
            for key in ('glyphs', 'sprite'):
                self.assertTrue(style[key].startswith('https://maps.nowave.example/'))
            for source in style['sources'].values():
                for url in source.get('tiles', []):
                    if '/tiles/vector/' in url or '/tiles/bathymetry/' in url:
                        self.assertTrue(url.startswith('https://maps.nowave.example/'))
                if isinstance(source.get('data'), str):
                    self.assertTrue(source['data'].startswith('https://maps.nowave.example/'))
            self.assertNotIn('http://127.0.0.1', json.dumps(style))
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
