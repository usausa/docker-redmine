// 添付画像のサムネイルをクリックしたとき、別ページへ移らずに画面上で拡大表示する
// （redmine_lightbox2 の代替。Esc か画像の外をクリックで閉じる。← → で前後の画像）
$(function () {
  var $links = $('div.thumbnails a[href*="/attachments/"]');
  if (!$links.length) return;
  var urls = $links.map(function () {
    return $(this).attr('href').replace(/\/attachments\/(\d+).*$/, '/attachments/download/$1');
  }).get();
  $('<style>').text(
    '#vc-lightbox{position:fixed;inset:0;z-index:10000;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.8);cursor:zoom-out}' +
    '#vc-lightbox img{max-width:92vw;max-height:88vh;background:#fff;box-shadow:0 0 24px #000}' +
    '#vc-lightbox .vc-lb-info{position:absolute;bottom:12px;color:#fff;font-size:14px}'
  ).appendTo('head');
  var $box = $('<div id="vc-lightbox"><img alt=""><span class="vc-lb-info"></span></div>').appendTo('body');
  var index = 0;
  function show(i) {
    index = (i + urls.length) % urls.length;
    $box.find('img').attr('src', urls[index]);
    $box.find('.vc-lb-info').text((index + 1) + ' / ' + urls.length + '（Esc で閉じる / ← → で切り替え）');
    $box.css('display', 'flex');
  }
  $links.on('click', function (e) {
    e.preventDefault();
    show($links.index(this));
  });
  $box.on('click', function () { $box.hide(); });
  $(document).on('keydown', function (e) {
    if (!$box.is(':visible')) return;
    if (e.key === 'Escape') $box.hide();
    else if (e.key === 'ArrowRight') show(index + 1);
    else if (e.key === 'ArrowLeft') show(index - 1);
  });
});
