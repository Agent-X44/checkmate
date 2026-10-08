class PdfAlignment {
  final double nameTop;
  final double nameLeft;
  final double nameScale;
  final double qrTop;
  final double qrRight;
  final double qrSize;
  final double setATop;
  final double setALeft;

  const PdfAlignment({
    this.nameTop = 115.8,
    this.nameLeft = 172.5,
    this.nameScale = 1.0,
    this.qrTop = 57.0,
    this.qrRight = 99.6,
    this.qrSize = 107.0,
    this.setATop = 175,
    this.setALeft = 145,
  });

  /// Default alignment for templates using 'assets/50_questions.png'
  const PdfAlignment.for50Questions()
      : nameTop = 115.8,
        nameLeft = 172.5,
        nameScale = 1.0,
        qrTop = 57.0,
        qrRight = 99.6,
        qrSize = 107.0,
        setATop = 175.0,
        setALeft = 145.0;

  /// Default alignment for templates using 'assets/30_questions.png'
  const PdfAlignment.for30Questions()
      : nameTop = 140.6,
        nameLeft = 129.1,
        nameScale = 0.8,
        qrTop = 95,
        qrRight = 40,
        qrSize = 110.5,
        setATop = 175.0,
        setALeft = 145.0;
}
