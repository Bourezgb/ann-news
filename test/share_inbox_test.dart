import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:ann_news/models/news_input.dart';
import 'package:ann_news/services/share_inbox.dart';

Future<String> _keep(String p) async => 'kept:$p';

void main() {
  test('shared link with a short title becomes a single url input', () async {
    final r = await ShareInbox.convert(
      'وزير الصحة يستقبل وفداً https://www.sante.gov.dz/news/123',
      SharedMediaType.text,
      'text/plain',
      keepFile: _keep,
    );
    expect(r.map((i) => i.kind), [InputKind.url]);
    expect(r.single.value, 'https://www.sante.gov.dz/news/123');
  });

  test('youtube links are detected', () async {
    final r = await ShareInbox.convert('https://youtu.be/abc123', SharedMediaType.url, null, keepFile: _keep);
    expect(r.single.kind, InputKind.youtube);
  });

  test('plain text stays text', () async {
    final r = await ShareInbox.convert('نص بيان كامل من المديرية', SharedMediaType.text, 'text/plain', keepFile: _keep);
    expect(r.single.kind, InputKind.text);
  });

  test('files are kept and typed by mime', () async {
    final audio = await ShareInbox.convert('/c/a.m4a', SharedMediaType.file, 'audio/mp4', keepFile: _keep);
    expect(audio.single.kind, InputKind.audio);
    expect(audio.single.value, 'kept:/c/a.m4a');
    final img = await ShareInbox.convert('/c/i.jpg', SharedMediaType.image, 'image/jpeg', keepFile: _keep);
    expect(img.single.kind, InputKind.image);
    final pdf = await ShareInbox.convert('/c/d.pdf', SharedMediaType.file, 'application/pdf', keepFile: _keep);
    expect(pdf, isEmpty);
  });
}
