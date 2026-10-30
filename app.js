// نسخة واجهة فقط: المصادقة والتحقق من الاشتراك غير مفعّلين في هذه الحزمة.
const form = document.getElementById('login-form');
form.addEventListener('submit', function (event) {
  event.preventDefault();
  const code = document.getElementById('student-code').value.trim();
  const phone = document.getElementById('phone').value.trim();
  const message = document.getElementById('form-message');

  if (!code || !phone) {
    message.textContent = 'من فضلك أكمل كود الطالب ورقم الهاتف.';
    return;
  }

  message.textContent =
    'هذه نسخة واجهة تجريبية. سيتم تفعيل التحقق الآمن وربط المرحلة والصف بملف الطالب بعد إعداد قاعدة البيانات.';
});
