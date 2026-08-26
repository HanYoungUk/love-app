// 캡쳐 이미지에서 글자를 읽어내는 브라우저 내 OCR.
// tesseract.js를 쓰며, 필요한 파일은 전부 이 앱 도메인에서 받는다(외부 CDN 불필요).
// Dart 쪽에서는 window.loveOcr.run(dataUrl) / window.loveOcr.pixel(x, y) 만 사용한다.
(function () {
  var worker = null;
  var loading = null;
  var canvas = null;
  var ctx = null;
  // 워커는 한 번만 만들기 때문에, logger가 늘 최신 콜백을 보도록 여기에 담아둔다
  var progressCb = null;

  // tesseract.min.js 를 처음 쓸 때만 내려받는다 (앱 시작 속도에 영향 없게)
  function loadScript() {
    if (window.Tesseract) return Promise.resolve();
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = 'ocr/tesseract.min.js';
      s.onload = resolve;
      s.onerror = function () { reject(new Error('tesseract.min.js 로드 실패')); };
      document.head.appendChild(s);
    });
  }

  function getWorker() {
    if (worker) return Promise.resolve(worker);
    if (loading) return loading;
    loading = loadScript()
      .then(function () {
        return window.Tesseract.createWorker('kor+eng', 1, {
          workerPath: 'ocr/worker.min.js',
          corePath: 'ocr/core',
          langPath: 'ocr/lang',
          gzip: true,
          logger: function (m) {
            if (progressCb && m && typeof m.progress === 'number') {
              progressCb(m.status + '|' + m.progress);
            }
          },
        });
      })
      .then(function (w) {
        worker = w;
        loading = null;
        return w;
      })
      .catch(function (e) {
        loading = null;
        throw e;
      });
    return loading;
  }

  // 색 추출용으로 원본 이미지를 캔버스에 올려둔다
  function drawToCanvas(dataUrl) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.onload = function () {
        canvas = document.createElement('canvas');
        canvas.width = img.naturalWidth;
        canvas.height = img.naturalHeight;
        ctx = canvas.getContext('2d', { willReadFrequently: true });
        ctx.drawImage(img, 0, 0);
        resolve({ width: img.naturalWidth, height: img.naturalHeight });
      };
      img.onerror = function () { reject(new Error('이미지를 열 수 없습니다')); };
      img.src = dataUrl;
    });
  }

  window.loveOcr = {
    /// dataUrl(이미지) → JSON 문자열 {width, height, lines:[{text, x0, y0, x1, y1, conf}]}
    run: function (dataUrl, onProgress) {
      progressCb = onProgress || null;
      return drawToCanvas(dataUrl)
        .then(function (size) {
          return getWorker().then(function (w) {
            return w.recognize(dataUrl, {}, { blocks: true }).then(function (res) {
              var lines = [];
              var blocks = (res.data && res.data.blocks) || [];
              blocks.forEach(function (b) {
                (b.paragraphs || []).forEach(function (p) {
                  (p.lines || []).forEach(function (l) {
                    // 단어 좌표가 있어야 아바타 글자를 걸러내고 띄어쓰기를 복원할 수 있다
                    var words = (l.words || [])
                      .map(function (w) {
                        return {
                          text: (w.text || '').trim(),
                          x0: w.bbox.x0, x1: w.bbox.x1,
                        };
                      })
                      .filter(function (w) { return w.text; });
                    if (!words.length) return;
                    lines.push({
                      words: words,
                      x0: l.bbox.x0, y0: l.bbox.y0,
                      x1: l.bbox.x1, y1: l.bbox.y1,
                      conf: l.confidence,
                    });
                  });
                });
              });
              lines.sort(function (a, b) { return a.y0 - b.y0; });
              return JSON.stringify({
                width: size.width, height: size.height, lines: lines,
              });
            });
          });
        });
    },

    /// 캔버스의 (x, y) 픽셀 색을 0xAARRGGBB 정수로 반환. 범위 밖이면 0.
    pixel: function (x, y) {
      if (!ctx || !canvas) return 0;
      x = Math.max(0, Math.min(canvas.width - 1, Math.round(x)));
      y = Math.max(0, Math.min(canvas.height - 1, Math.round(y)));
      var d = ctx.getImageData(x, y, 1, 1).data;
      // >>> 0 : 부호 없는 32비트로 (Dart Color가 그대로 받게)
      return (((255 << 24) | (d[0] << 16) | (d[1] << 8) | d[2]) >>> 0);
    },
  };
})();
