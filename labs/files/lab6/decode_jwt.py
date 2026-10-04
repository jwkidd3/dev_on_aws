"""Decode the payload (middle part) of one or more JWTs — no signature check.

    python3 decode_jwt.py "$ID_TOKEN"                    # full payload
    python3 decode_jwt.py "$ID_TOKEN" "$BOB_TOKEN" --sub  # just each sub

JWT parts are base64url WITHOUT padding, which is why `base64 -d` chokes on
them; we restore the padding before decoding.
"""
import base64
import json
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
for token in args:
    part = token.split(".")[1]
    part += "=" * (-len(part) % 4)
    claims = json.loads(base64.urlsafe_b64decode(part))
    print(claims["sub"] if "--sub" in sys.argv else json.dumps(claims, indent=2))
