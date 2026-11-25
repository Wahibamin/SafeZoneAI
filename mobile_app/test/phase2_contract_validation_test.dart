import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/errors/app_exceptions.dart';
import 'package:safezone_mobile/features/models/domain/model_contract_validator.dart';

// Tensor-description unit doubles only, not TFLite files or device inference.
Map<String, dynamic> inspection() => {
      'inputs': [
        {
          'shape': [1, 640, 640, 3],
          'shape_signature': [1, 640, 640, 3],
          'dtype': 'float32',
          'scale': 0.0
        }
      ],
      'outputs': [
        {
          'shape': [1, 7, 8400],
          'shape_signature': [1, 7, 8400],
          'dtype': 'float32',
          'scale': 0.0
        }
      ],
      'embedded': {
        'safezone': {
          'output': {'coordinates': 'normalized'}
        },
        'ultralytics': {
          'description': 'Ultralytics YOLO11',
          'task': 'detect',
          'imgsz': [640, 640],
          'names': {
            '0': 'with_mask',
            '1': 'without_mask',
            '2': 'mask_weared_incorrect'
          },
          'args': {'nms': false}
        }
      },
      'size_bytes': 1234,
    };
void main() {
  test(
      'reads tensor dimensions/classes without inventing a mask safety mapping',
      () {
    final contract = ModelContractValidator.validate(
        actual: inspection(), manifest: {}, digest: 'abc');
    expect((contract['input'] as Map)['width'], 640);
    expect((contract['output'] as Map)['layout'], 'BCN');
    expect((contract['mapping'] as Map).values.toSet(), {'review'});
  });
  final contradictions = <String, Map<String, dynamic>>{
    'hash bypass': {'sha256': 'SKIP_VERIFY_IN_TEST'},
    'task': {'task': 'classify'},
    'width': {
      'input': {'width': 320}
    },
    'height': {
      'input': {'height': 320}
    },
    'input layout': {
      'input': {'layout': 'NCHW'}
    },
    'input dtype': {
      'input': {'dtype': 'int8'}
    },
    'color': {
      'input': {'color': 'BGR'}
    },
    'input shape': {
      'input': {
        'shape': [1, 3, 640, 640]
      }
    },
    'output shape': {
      'output': {
        'shape': [1, 8400, 7]
      }
    },
    'output layout': {
      'output': {'layout': 'BNC'}
    },
    'output dtype': {
      'output': {'dtype': 'uint8'}
    },
    'nms': {
      'output': {'nms': true}
    },
    'classes': {
      'classes': {'0': 'helmet'}
    },
    'mapping': {
      'mapping': {'unknown': 'compliant'}
    },
    'normalization': {
      'input': {
        'normalization': {
          'mean': [0.0],
          'std': [1.0]
        }
      }
    },
    'schema': {'schema_version': 99},
    'format': {'format': 'onnx'},
  };
  for (final item in contradictions.entries) {
    test('rejects manifest contradiction: ${item.key}', () {
      expect(
          () => ModelContractValidator.validate(
              actual: inspection(), manifest: item.value, digest: 'abc'),
          throwsA(isA<ModelValidationException>()));
    });
  }
  test('rejects malformed and placeholder manifests', () {
    for (final text in ['[]', '{', '{"sha256":"<CALCULATE_AFTER_EXPORT>"}']) {
      expect(() => ModelContractValidator.manifest(text),
          throwsA(isA<ModelValidationException>()));
    }
    expect(ModelContractValidator.manifest(null), isEmpty);
  });
  test('requires explicit coordinate units and honors actual pixel outputs', () {
    final actual = inspection();
    (actual['embedded'] as Map).remove('safezone');
    expect(() => ModelContractValidator.validate(actual: actual, manifest: {}, digest: 'abc'),
      throwsA(isA<ModelValidationException>()));
    final contract = ModelContractValidator.validate(actual: actual,
      manifest: {'output': {'coordinates': 'pixels'}}, digest: 'abc');
    expect((contract['output'] as Map)['coordinates'], 'pixels');
  });
  test('YOLO26 end-to-end uses its separate six-column adapter', () {
    final actual = inspection();
    final ultra = actual['embedded']['ultralytics'] as Map;
    ultra['description'] = 'Ultralytics YOLO26n';
    ultra['end2end'] = true;
    actual['outputs'][0]['shape'] = [1, 300, 6];
    actual['outputs'][0]['shape_signature'] = [1, 300, 6];
    final contract = ModelContractValidator.validate(actual: actual,
      manifest: {'family':'YOLO26n', 'output':{'adapter':'yolo26_end2end','coordinates':'normalized'}}, digest:'abc');
    expect(contract['output']['adapter'], 'yolo26_end2end');
    expect(contract['output']['layout'], 'BNC');
  });
  test(
      'rejects wrong class count, dynamic shape, multiple outputs and quantization without scale',
      () {
    for (var i = 0; i < 4; i++) {
      final actual =
          jsonDecode(jsonEncode(inspection())) as Map<String, dynamic>;
      if (i == 0) (actual['outputs'] as List).first['shape'] = [1, 8, 8400];
      if (i == 1) {
        (actual['inputs'] as List).first['shape_signature'] = [-1, 640, 640, 3];
      }
      if (i == 2) {
        (actual['outputs'] as List).add({
          'shape': [1]
        });
      }
      if (i == 3) (actual['inputs'] as List).first['dtype'] = 'int8';
      expect(
          () => ModelContractValidator.validate(
              actual: actual, manifest: {}, digest: 'abc'),
          throwsA(isA<ModelValidationException>()));
    }
  });
}
