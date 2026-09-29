import 'dart:math' as math;

enum FilterType {
  highPass,
  lowPass,
}

/// High-precision Second-Order Infinite Impulse Response (IIR) Biquad Filter in Dart.
///
/// Implements standard Direct Form II Transposed equations derived from the
/// Robert Bristow-Johnson (RBJ) Audio EQ Cookbook for maximal numerical stability
/// and minimal quantization noise.
///
/// Transfer function:
/// H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
class BiquadFilter {
  final FilterType type;
  final double cutoffFreq;
  final double sampleRate;
  final double q;

  // Normalized coefficients
  double b0 = 0.0;
  double b1 = 0.0;
  double b2 = 0.0;
  double a1 = 0.0;
  double a2 = 0.0;

  // Direct Form II Transposed state registers
  double z1 = 0.0;
  double z2 = 0.0;

  BiquadFilter({
    required this.type,
    required this.cutoffFreq,
    required this.sampleRate,
    double? q,
  }) : q = q ?? 0.7071067811865475 {
    _configure();
  }

  void _configure() {
    final double nyquist = sampleRate / 2.0;
    double fc = math.min(cutoffFreq, nyquist * 0.99);
    fc = math.max(fc, 1.0);

    final double omega0 = 2.0 * math.pi * fc / sampleRate;
    final double alpha = math.sin(omega0) / (2.0 * q);
    final double cosOmega0 = math.cos(omega0);

    double rawB0, rawB1, rawB2;
    double rawA0, rawA1, rawA2;

    if (type == FilterType.lowPass) {
      rawB0 = (1.0 - cosOmega0) / 2.0;
      rawB1 = 1.0 - cosOmega0;
      rawB2 = (1.0 - cosOmega0) / 2.0;
      rawA0 = 1.0 + alpha;
      rawA1 = -2.0 * cosOmega0;
      rawA2 = 1.0 - alpha;
    } else {
      rawB0 = (1.0 + cosOmega0) / 2.0;
      rawB1 = -(1.0 + cosOmega0);
      rawB2 = (1.0 + cosOmega0) / 2.0;
      rawA0 = 1.0 + alpha;
      rawA1 = -2.0 * cosOmega0;
      rawA2 = 1.0 - alpha;
    }

    // Normalize all coefficients by a0
    b0 = rawB0 / rawA0;
    b1 = rawB1 / rawA0;
    b2 = rawB2 / rawA0;
    a1 = rawA1 / rawA0;
    a2 = rawA2 / rawA0;

    resetState();
  }

  void resetState() {
    z1 = 0.0;
    z2 = 0.0;
  }

  /// Processes single sample x[n] normalized in [-1.0, 1.0] using Direct Form II Transposed:
  /// y[n] = b0*x[n] + z1
  /// z1   = b1*x[n] - a1*y[n] + z2
  /// z2   = b2*x[n] - a2*y[n]
  double process(double x) {
    final double y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }
}
