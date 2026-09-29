import 'dart:math' as math;

/// PASS 2: Heart & Artifact Separation via Discrete Wavelet Transform (DWT) using db8 in Dart.
class DwtDb8 {
  // Daubechies 8 (db8) 16-tap Low-pass Decomposition Filter coefficients (Lo_D)
  static const List<double> h = [
    -0.00011747233804595679,
     0.0006754494059985568,
    -0.001523892856294792,
    -0.0005710441908683522,
     0.010533077723530467,
    -0.03224486958450811,
    -0.03535925835929424,
     0.37740285561283066,
     0.7805187802879577,
     0.3976377417702224,
    -0.08230105910865824,
    -0.02787990694202868,
     0.03523877377013813,
    -0.004944002638848449,
    -0.0001600818227914772,
     0.0000325114055765205,
  ];

  static const int filterLen = 16;
  static final List<double> g = List.generate(
    filterLen,
    (i) => ((i % 2 == 0) ? 1.0 : -1.0) * h[filterLen - 1 - i],
  );
  static final List<double> hRec = List.generate(
    filterLen,
    (i) => h[filterLen - 1 - i],
  );
  static final List<double> gRec = List.generate(
    filterLen,
    (i) => ((i % 2 == 0) ? -1.0 : 1.0) * h[i],
  );

  /// Performs db8 DWT decomposition, soft-thresholding on cardiac subbands, and IDWT reconstruction.
  static List<double> separateHeartAndArtifacts(List<double> input, int sampleRate) {
    if (input.length < filterLen * 4) {
      return List<double>.from(input);
    }

    final int origLen = input.length;
    final int levels = math.min(5, (math.log(origLen / filterLen) / math.ln2).floor());
    if (levels < 2) return List<double>.from(input);

    final List<List<double>> detailCoeffs = [];
    final List<int> lengths = [];
    List<double> approx = List<double>.from(input);

    for (int l = 0; l < levels; l++) {
      lengths.add(approx.length);
      final step = _dwtStep(approx);
      approx = step[0];
      detailCoeffs.add(step[1]);
    }

    // Soft thresholding on cardiac subbands
    for (int l = 0; l < detailCoeffs.length; l++) {
      if (l >= 2) {
        _applySoftThreshold(detailCoeffs[l], 2.2);
      }
    }

    _applyCardiacSpikeAttenuation(approx);

    // Inverse DWT
    for (int l = levels - 1; l >= 0; l--) {
      approx = _idwtStep(approx, detailCoeffs[l], lengths[l]);
    }

    if (approx.length > origLen) {
      return approx.sublist(0, origLen);
    } else if (approx.length < origLen) {
      final padded = List<double>.filled(origLen, 0.0);
      padded.setRange(0, approx.length, approx);
      return padded;
    }
    return approx;
  }

  static List<List<double>> _dwtStep(List<double> x) {
    final int n = x.length;
    final int halfLen = (n + 1) ~/ 2;
    final List<double> cA = List.filled(halfLen, 0.0);
    final List<double> cD = List.filled(halfLen, 0.0);

    for (int i = 0; i < halfLen; i++) {
      final int center = i * 2;
      double sumA = 0.0;
      double sumD = 0.0;

      for (int k = 0; k < filterLen; k++) {
        int idx = center + k - (filterLen ~/ 2);
        if (idx < 0) {
          idx = -idx - 1;
        } else if (idx >= n) {
          idx = 2 * n - 1 - idx;
        }
        if (idx < 0) idx = 0;
        if (idx >= n) idx = n - 1;

        sumA += x[idx] * h[k];
        sumD += x[idx] * g[k];
      }
      cA[i] = sumA;
      cD[i] = sumD;
    }

    return [cA, cD];
  }

  static List<double> _idwtStep(List<double> cA, List<double> cD, int targetLen) {
    final int nA = cA.length;
    final List<double> out = List.filled(targetLen, 0.0);
    final int outHalf = (targetLen + 1) ~/ 2;
    final int limit = math.min(nA, outHalf);

    for (int i = 0; i < limit; i++) {
      final int center = i * 2;
      for (int k = 0; k < filterLen; k++) {
        final int outIdx = center + k - (filterLen ~/ 2);
        if (outIdx >= 0 && outIdx < targetLen) {
          out[outIdx] += cA[i] * hRec[k] + cD[i] * gRec[k];
        }
      }
    }
    return out;
  }

  static void _applySoftThreshold(List<double> subband, double multiplier) {
    if (subband.isEmpty) return;

    final List<double> absVals = subband.map((v) => v.abs()).toList()..sort();
    final double median = absVals[absVals.length ~/ 2];
    final double sigma = median / 0.6745;
    final double threshold = multiplier * sigma * math.sqrt(2.0 * math.log(math.max(2, subband.length)));

    if (threshold <= 0.00001) return;

    for (int i = 0; i < subband.length; i++) {
      final double v = subband[i];
      final double absV = v.abs();
      if (absV > threshold) {
        subband[i] = (v.sign) * (absV - 0.75 * threshold);
      }
    }
  }

  static void _applyCardiacSpikeAttenuation(List<double> approx) {
    if (approx.isEmpty) return;
    double sum = 0.0;
    for (final v in approx) {
      sum += v.abs();
    }
    final double meanAbs = sum / approx.length;
    final double threshold = meanAbs * 2.8;

    for (int i = 0; i < approx.length; i++) {
      final double abs = approx[i].abs();
      if (abs > threshold) {
        final double excess = abs - threshold;
        approx[i] = approx[i].sign * (threshold + excess * 0.25);
      }
    }
  }
}
