// reCAPTCHA callback (data-callback="enableSubmit" on the widget in contact.md)
function enableSubmit() {
  var btn = document.getElementById('form_submit');
  btn.disabled = false;
  btn.title = '';
}
