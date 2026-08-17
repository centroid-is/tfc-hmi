/// Tiny deterministic images for image-asset tests.
///
/// All three rasters are the same 48x32 quadrant pattern (red / gold over
/// blue / green with a white diagonal), generated once with PIL and frozen
/// here as base64 — non-square and asymmetric on purpose, so aspect-ratio
/// handling, BoxFit and rotation are all visible in renders and goldens.
library;

import 'dart:convert';
import 'dart:typed_data';

const String fixturePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAAA5UlEQVR42s3UwRGDIBCFYXnV'
    'sBXQSzzYVe4erCNXrWDrsAJzyAzDaGKQhV05iYDzz8eMbvY+MC9EnWz4Z1dluG3b4kSSVSsI'
    'C1HsCMyd9cDOJjDbZiG9rztQYTc3p8LxlS0Vfi1YUeFkzYQKf3coUyFnkyYV8rfqUOHSbgUq'
    'FJxpSoWyY+2o3Oy95Hxas76oQpB/zPKv8BQ+DzT2twhKm4RZqHX3NPaxg4fJPmhnw8NUloXq'
    'PxIhVf0gIVWroGKqhkFlVM2DrlJpBF2i0gvKpFINyqEyCDqnsgk6obIM+kplHHSkegMUV45C'
    '6+Yu2AAAAABJRU5ErkJggg==';

const String fixtureJpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoM'
    'DAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsN'
    'FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAAR'
    'CAAgADADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAA'
    'AgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkK'
    'FhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
    'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl'
    '5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
    'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYk'
    'NOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOE'
    'hYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk'
    '5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwC5o/xL8C/F3SbPQfifYReGtWtY5RaeONAs'
    'Y4mAWJUggurSGICSNQiqpTBASNRsBdzw/wAUvgh4o+Ek1tJqtvFf6LdxxS2ev6UzT6ddiRC6'
    'iObaAThW+U4JC7gCpDHgK9G+FHxw1r4XeZppt7XxD4PvLhJ9T8M6rCk1pebe+HVvLfhSHUfe'
    'jjLBgoWvgVUjV0q79/8APv8An6n9bywlfAtzwGsetNvT/tx/Zfl8O3w6s85r9C6+a7/4LeHP'
    'i3o1xr3wgupZNQtLJr7VvA2oSNJf2h8zBFm+wC5jAPHO8AJkl5Qg+l5oZLeZ4pUaKVGKujjD'
    'KRwQR2NfmHG1KUPq7e3va9Psnyue42li/ZKF1KPNeL0ktt159Grp7ptDKKKK/Lz5U/PSiiiv'
    '9hT+QSewv7nS763vbK4ltLy2kWaG4gcpJE6nKsrDkEEAgjkEV9WW/wASvC3xegSx+JsX9k64'
    'POkj8a6XbKJXbYBHHdQRp+9UbQAy4YBUUbQXc/Jlel1+M+IsuV4S3Xn/APbDz8XiZ0OVLWLv'
    'dPVPbf8AzVmujO0+Inwi8Q/DSWCTUYY73SrlI5LXWtOYzWNyHUsuyXABOA3ynBwMgFSCeLru'
    'vht8XdV+Hm+wMFtrfhe6nSbUPD+oxJLbXW3vhlOxuFIYd0TcGCgV1F58KNC+JelT6z8MLiR7'
    '22tWvNS8IXrs95bfvMYtX2gXEYB4534CZJeQIPxvlUtYfd/W55zw1PErmwm/WD3/AO3X9pf+'
    'TeTWp//Z';

const String fixtureBmpBase64 =
    'Qk02EgAAAAAAADYAAAAoAAAAMAAAACAAAAABABgAAAAAAAASAADEDgAAxA4AAAAAAAAAAAAA'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo////////////yFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAo////////////WqAoyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo////////////////WqAoWqAo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAo////////////WqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo////////////'
    '////WqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo////////////WqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    '////////////////WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo////////////WqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAo////////////////WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo////////////WqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'WqAoWqAoWqAoWqAoWqAoWqAo////////////////WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooWqAoWqAoWqAoWqAoWqAo////'
    '////////WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooWqAoWqAoWqAo////////////////WqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'WqAoWqAo////////////WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo////////////////WqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'yFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFooyFoo'
    'yFooyFooyFooyFooyFoo////////////WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAo'
    'WqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoWqAoKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI////////////'
    '////KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI////////////KCjIKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    '////////////////KCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI////////////KCjIKCjIKCjIKCjI'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjI////////////////KCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI////////////KCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjI////////////////KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI////'
    '////////KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI////////////////KCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjI////////////KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjIKCjIKCjIKCjI////////////////KCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KCjIKCjIKCjIKCjIKCjI////////////KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjIKCjI////////////'
    '////KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKCjIKCjI////////////KCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    '////////////////KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKCjI////KCjIKCjIKCjIKCjI'
    'KCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjIKCjI'
    'KL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7wKL7w'
    'KL7wKL7wKL7wKL7wKL7wKL7w';

Uint8List get fixturePngBytes => base64Decode(fixturePngBase64);
Uint8List get fixtureJpegBytes => base64Decode(fixtureJpegBase64);
Uint8List get fixtureBmpBytes => base64Decode(fixtureBmpBase64);

/// A 3:2 SVG with the same quadrant layout as the rasters.
const String fixtureSvgText = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 32">
  <rect width="24" height="16" fill="#c82828"/>
  <rect x="24" width="24" height="16" fill="#f0be28"/>
  <rect y="16" width="24" height="16" fill="#285ac8"/>
  <rect x="24" y="16" width="24" height="16" fill="#28a05a"/>
  <line x1="0" y1="0" x2="48" y2="32" stroke="white" stroke-width="2"/>
</svg>
''';

Uint8List get fixtureSvgBytes => Uint8List.fromList(utf8.encode(fixtureSvgText));
