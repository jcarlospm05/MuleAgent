import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

String xml(Object? value) => value
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
    .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');

class WorkbookSheet {
  WorkbookSheet(this.name, this.rows, {this.photos = const {}});
  final String name;
  final List<List<Object?>> rows;

  /// Excel row number -> JPEG thumbnail, anchored in column G.
  final Map<int, Uint8List> photos;
}

Uint8List workbook(List<WorkbookSheet> sheets) {
  final archive = Archive();
  void text(String path, String data) {
    final bytes = utf8.encode(data);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';
  text(
    '_rels/.rels',
    '<?xml version="1.0"?><Relationships xmlns="$pkg"><Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  text(
    'xl/workbook.xml',
    '<?xml version="1.0"?><workbook xmlns="$ns" xmlns:r="$rel"><sheets>${List.generate(sheets.length, (i) => '<sheet name="${xml(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>').join()}</sheets></workbook>',
  );
  text(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0"?><Relationships xmlns="$pkg">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="$rel/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>',
  );
  String column(int n) {
    var result = '';
    n++;
    while (n > 0) {
      n--;
      result = String.fromCharCode(65 + n % 26) + result;
      n = n ~/ 26;
    }
    return result;
  }

  for (var i = 0; i < sheets.length; i++) {
    final sheet = sheets[i], number = i + 1;
    final rows = List.generate(
      sheet.rows.length,
      (r) =>
          '<row r="${r + 1}"${sheet.photos.containsKey(r + 1) ? ' ht="85" customHeight="1"' : ''}>${List.generate(sheet.rows[r].length, (c) => '<c r="${column(c)}${r + 1}" t="inlineStr"><is><t xml:space="preserve">${xml(sheet.rows[r][c] ?? '')}</t></is></c>').join()}</row>',
    ).join();
    text(
      'xl/worksheets/sheet$number.xml',
      '<?xml version="1.0"?><worksheet xmlns="$ns" xmlns:r="$rel"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="6" width="24" customWidth="1"/><col min="7" max="7" width="30" customWidth="1"/><col min="8" max="15" width="24" customWidth="1"/></cols><sheetData>$rows</sheetData>${sheet.photos.isEmpty ? '' : '<drawing r:id="rId1"/>'}</worksheet>',
    );
    if (sheet.photos.isNotEmpty) {
      text(
        'xl/worksheets/_rels/sheet$number.xml.rels',
        '<?xml version="1.0"?><Relationships xmlns="$pkg"><Relationship Id="rId1" Type="$rel/drawing" Target="../drawings/drawing$number.xml"/></Relationships>',
      );
      final anchors = StringBuffer(), relationships = StringBuffer();
      var photo = 0;
      for (final entry in sheet.photos.entries) {
        photo++;
        final filename = 'image${number}_$photo.jpg';
        archive.addFile(
          ArchiveFile('xl/media/$filename', entry.value.length, entry.value),
        );
        relationships.write(
          '<Relationship Id="rId$photo" Type="$rel/image" Target="../media/$filename"/>',
        );
        anchors.write(
          '<xdr:oneCellAnchor><xdr:from><xdr:col>6</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${entry.key - 1}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="1714500" cy="952500"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="$photo" name="Evidencia $photo"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId$photo"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1714500" cy="952500"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>',
        );
      }
      text(
        'xl/drawings/drawing$number.xml',
        '<?xml version="1.0"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$rel">$anchors</xdr:wsDr>',
      );
      text(
        'xl/drawings/_rels/drawing$number.xml.rels',
        '<?xml version="1.0"?><Relationships xmlns="$pkg">$relationships</Relationships>',
      );
    }
  }
  text(
    '[Content_Types].xml',
    '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>${sheets[i].photos.isEmpty ? '' : '<Override PartName="/xl/drawings/drawing${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'}').join()}</Types>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
