(function () {
  var root = document.documentElement;
  var btn = document.getElementById('lang');

  function apply(lang) {
    root.lang = lang;
    root.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.querySelectorAll('[data-ar]').forEach(function (el) {
      el.textContent = el.getAttribute('data-' + lang);
    });
    btn.textContent = lang === 'ar' ? 'EN' : 'عربي';
    document.title = lang === 'ar' ? 'منطقة الصفر | Zero Zone' : 'Zero Zone | منطقة الصفر';
    try { localStorage.setItem('zz-lang', lang); } catch (e) {}
  }

  var saved = (navigator.language || '').slice(0, 2) === 'en' ? 'en' : 'ar';
  try { saved = localStorage.getItem('zz-lang') || saved; } catch (e) {}
  apply(saved === 'en' ? 'en' : 'ar');

  btn.addEventListener('click', function () {
    apply(root.lang === 'ar' ? 'en' : 'ar');
  });
})();
