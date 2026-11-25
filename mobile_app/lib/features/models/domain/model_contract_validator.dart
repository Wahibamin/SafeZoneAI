import 'dart:convert';
import '../../../core/errors/app_exceptions.dart';

/// Conservative P02 adapter: static NHWC RGB, raw YOLOv8/11 BCN or BNC output.
class ModelContractValidator {
  static Never fail(String message) => throw ModelValidationException(message);
  static Map<String, dynamic> manifest(String? text) {
    if (text == null || text.trim().isEmpty) return {};
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic>) fail('يلزم كائن JSON في model.json.');
      if (RegExp(r'<[^>]+>').hasMatch(text)) {
        fail('قيم model.json النائبة غير مكتملة.');
      }
      return value;
    } on FormatException {
      fail('ملف model.json غير صالح.');
    }
  }

  static Map<String, String> labelsOf(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    if (raw is List) {
      return {for (var i = 0; i < raw.length; i++) '$i': raw[i].toString()};
    }
    return {};
  }

  static Map<String, dynamic> validate(
      {required Map<String, dynamic> actual,
      required Map<String, dynamic> manifest,
      required String digest}) {
    void same(dynamic declared, dynamic observed, String field) {
      if (declared != null && !_equivalent(declared, observed)) {
        fail('تعارض $field مع بيانات النموذج الفعلية ($observed).');
      }
    }

    same(manifest['schema_version'], 1, 'schema_version');
    same(manifest['sha256'], digest, 'SHA-256');
    same(manifest['format'], 'tflite', 'format');
    final inputs = actual['inputs'] as List;
    final outputs = actual['outputs'] as List;
    if (inputs.length != 1 || outputs.length != 1) {
      fail('يلزم دخل واحد وخرج واحد لكشف YOLO الخام.');
    }
    final input = Map<String, dynamic>.from(inputs.single as Map);
    final output = Map<String, dynamic>.from(outputs.single as Map);
    final shape = List<int>.from(input['shape'] as List);
    final outShape = List<int>.from(output['shape'] as List);
    if (shape.length != 4 ||
        shape[0] != 1 ||
        shape[3] != 3 ||
        shape.any((n) => n <= 0)) {
      fail('يلزم دخل NHWC [1,H,W,3] ثابت.');
    }
    for (final tensor in [input, output]) {
      final signature = tensor['shape_signature'] as List?;
      if (signature != null && signature.any((v) => (v as num) <= 0)) {
        fail('الأبعاد الديناميكية غير مدعومة.');
      }
      if (!['float32', 'uint8', 'int8'].contains(tensor['dtype'])) {
        fail('نوع التنسور غير مدعوم.');
      }
      if (tensor['dtype'] != 'float32' &&
          ((tensor['scale'] as num?) ?? 0) <= 0) {
        fail('معامل التكميم غير صالح.');
      }
    }
    final embedded =
        Map<String, dynamic>.from(actual['embedded'] as Map? ?? {});
    final ultra =
        Map<String, dynamic>.from(embedded['ultralytics'] as Map? ?? {});
    final safezone =
        Map<String, dynamic>.from(embedded['safezone'] as Map? ?? {});
    final task = ultra['task'] ?? manifest['task'];
    same(manifest['task'], task, 'task');
    if (task != 'detect') {
      fail('يلزم توثيق مهمة detect في البيانات المدمجة أو model.json.');
    }
    final description =
        '${embedded['name']} ${embedded['description']} ${ultra['description']}';
    final family = manifest['family'] as String?;
    final familyPattern =
        RegExp(r'yolo(?:v)?[0-9]+[nslmx]?', caseSensitive: false);
    final embeddedFamily =
        familyPattern.firstMatch(description)?.group(0)?.toLowerCase();
    final declaredFamily =
        familyPattern.firstMatch(family ?? '')?.group(0)?.toLowerCase();
    if (embeddedFamily != null &&
        declaredFamily != null &&
        embeddedFamily != declaredFamily) {
      fail('عائلة model.json تتعارض مع تعريف النموذج المدمج.');
    }
    if (!description.toLowerCase().contains('yolo') &&
        !(family?.toLowerCase().startsWith('yolo') ?? false)) {
      fail('يلزم تعريف عائلة YOLO في البيانات المدمجة أو model.json.');
    }
    final embeddedLabels = labelsOf(ultra['names'] ?? embedded['labels']);
    final associatedLabels = labelsOf(embedded['labels']);
    if (ultra['names'] != null &&
        associatedLabels.isNotEmpty &&
        !_equivalent(embeddedLabels, associatedLabels)) {
      fail('الفئات المدمجة تتعارض مع ملف الفئات داخل النموذج.');
    }
    final suppliedLabels = labelsOf(manifest['classes']);
    if (embeddedLabels.isNotEmpty &&
        suppliedLabels.isNotEmpty &&
        (embeddedLabels.length != suppliedLabels.length ||
            embeddedLabels.entries
                .any((e) => suppliedLabels[e.key] != e.value))) {
      fail('الفئات المرافقة تتعارض مع الفئات المدمجة.');
    }
    final labels = embeddedLabels.isNotEmpty ? embeddedLabels : suppliedLabels;
    if (labels.isEmpty ||
        labels.values.toSet().length != labels.length ||
        List.generate(labels.length, (i) => '$i')
            .any((k) => labels[k]?.trim().isEmpty ?? true)) {
      fail('يلزم ترقيم فئات متصل من الصفر وأسماء غير مكررة.');
    }
    final features = 4 + labels.length;
    final out = Map<String, dynamic>.from(manifest['output'] as Map? ?? {});
    final embeddedOut =
        Map<String, dynamic>.from(safezone['output'] as Map? ?? {});
    final coordinates = out['coordinates'] ?? embeddedOut['coordinates'];
    if (!['normalized', 'pixels'].contains(coordinates)) {
      fail(
          'يلزم توثيق وحدة إحداثيات الخرج normalized أو pixels في model.json أو safezone.json المدمج.');
    }
    same(out['coordinates'], embeddedOut['coordinates'] ?? coordinates,
        'output.coordinates');
    final end2end = (ultra['end2end'] == true ||
            out['adapter'] == 'yolo26_end2end' ||
            embeddedOut['adapter'] == 'yolo26_end2end') &&
        (declaredFamily ?? embeddedFamily ?? '').startsWith('yolo26');
    final endShape = outShape.length == 3 &&
        outShape[0] == 1 &&
        outShape[1] > 0 &&
        outShape[2] == 6;
    if (end2end &&
        (!endShape || !['normalized', 'pixels'].contains(coordinates))) {
      fail(
          'خرج YOLO26 يتطلب [1,N,6] وتوثيق output.coordinates (normalized أو pixels).');
    }
    if (!end2end &&
        (outShape.length != 3 ||
            outShape[0] != 1 ||
            !((outShape[1] == features && outShape[2] > features) ||
                (outShape[2] == features && outShape[1] > features)))) {
      fail(
          'الخرج $outShape لا يطابق كشف YOLO الخام وعدد الفئات ${labels.length}.');
    }
    final layout = end2end ? 'BNC' : (outShape[1] == features ? 'BCN' : 'BNC');
    if ((ultra['args'] as Map?)?['nms'] == true ||
        (ultra['end2end'] == true && !end2end)) {
      fail('تصدير NMS/end-to-end يحتاج محولًا آخر.');
    }
    final inp = Map<String, dynamic>.from(manifest['input'] as Map? ?? {});
    same(out['adapter'], end2end ? 'yolo26_end2end' : 'yolo_raw',
        'output.adapter');
    same(embeddedOut['adapter'], end2end ? 'yolo26_end2end' : 'yolo_raw',
        'embedded.output.adapter');
    same(inp['width'], shape[2], 'input.width');
    same(inp['height'], shape[1], 'input.height');
    same(inp['layout'], 'NHWC', 'input.layout');
    same(inp['shape'], shape, 'input.shape');
    same(inp['dtype'], input['dtype'], 'input.dtype');
    same(inp['color'], 'RGB', 'input.color');
    same(embedded['color'], 'RGB', 'embedded.color');
    for (final field in ['scale', 'zero_point']) {
      same(inp[field], input[field], 'input.$field');
      same(out[field], output[field], 'output.$field');
    }
    same(out['layout'], layout, 'output.layout');
    same(out['shape'], outShape, 'output.shape');
    same(out['dtype'], output['dtype'], 'output.dtype');
    same(out['nms'], false, 'output.nms');
    if (ultra['imgsz'] is List) {
      same(ultra['imgsz'], [shape[1], shape[2]], 'embedded.imgsz');
    }
    final normalization = embedded['normalization'] ??
        (ultra.isNotEmpty
            ? {
                'mean': [0.0],
                'std': [255.0]
              }
            : inp['normalization']);
    if (normalization is! Map) {
      fail('يلزم تحديد normalization كـ mean/std موثقين.');
    }
    final means = normalization['mean'] as List?;
    final stds = normalization['std'] as List?;
    if (means == null ||
        stds == null ||
        ![1, 3].contains(means.length) ||
        means.length != stds.length ||
        means.any((v) => v is! num || !v.isFinite || v != 0) ||
        stds.any((v) => v is! num || !v.isFinite || v <= 0)) {
      fail('المعالجة المدعومة RGB مع mean=0 وstd موجب بطول 1 أو 3.');
    }
    same(inp['normalization'], normalization, 'input.normalization');
    final mapping = Map<String, dynamic>.from(
        manifest['mapping'] as Map? ?? safezone['mapping'] as Map? ?? {});
    if (mapping.entries.any((e) =>
        !labels.values.contains(e.key) ||
        !['compliant', 'violation', 'review'].contains(e.value))) {
      fail('ربط السلامة غير صالح.');
    }
    return {
      'input': {
        ...input,
        'width': shape[2],
        'height': shape[1],
        'layout': 'NHWC',
        'color': 'RGB',
        'normalization': normalization
      },
      'output': {
        ...output,
        'layout': layout,
        'nms': false,
        'adapter': end2end ? 'yolo26_end2end' : 'yolo_raw',
        'coordinates': coordinates
      },
      'labels': labels,
      'task': task,
      'family': family ?? embedded['name'],
      'embedded': embedded,
      'mapping': {
        for (final label in labels.values) label: mapping[label] ?? 'review'
      },
      'size_bytes': actual['size_bytes']
    };
  }

  static bool _equivalent(dynamic a, dynamic b) {
    if (a is num && b is num) return a == b;
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i)
              .every((i) => _equivalent(a[i], b[i]));
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equivalent(a[k], b[k]));
    }
    return a == b;
  }
}
