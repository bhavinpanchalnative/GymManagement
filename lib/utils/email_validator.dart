final _emailPattern = RegExp(
  r"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$",
);

/// Validates the email format used by sign-in, sign-up, and password reset.
bool isValidEmailAddress(String value) => _emailPattern.hasMatch(value.trim());
