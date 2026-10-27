import 'package:alfaham_tv/data/models.dart';
import 'package:alfaham_tv/data/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseChannelLinks keeps main link first and de-duplicates', () {
    final links = parseChannelLinks({
      'links': {
        'b': {'url': 'http://b', 'label': 'احتياطي'},
        'a': {'url': 'http://a', 'label': 'الرئيسي'},
      },
      'url': 'http://a',
    });
    expect(links.first.url, 'http://a');
    expect(links.length, 2);
  });

  test('channel category ids follow categoryIds > categories > categoryId > catId', () {
    expect(Channel.fromJson('x', {'categoryIds': ['1', '2']}).categoryIds, ['1', '2']);
    expect(Channel.fromJson('x', {'categories': {'a': '9'}}).categoryIds, ['9']);
    expect(Channel.fromJson('x', {'catId': 7}).categoryIds, ['7']);
  });

  test('firebase key order puts numeric keys first', () {
    final keys = ['b', '10', 'a', '2'];
    keys.sort(firebaseKeyCompare);
    expect(keys, ['2', '10', 'a', 'b']);
  });

  test('search normalisation unifies alef/ta marbuta/ya', () {
    expect(normalizeSearchText('أخبارُ المَدينة'), normalizeSearchText('اخبار المدينه'));
  });
}
