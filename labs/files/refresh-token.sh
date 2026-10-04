# Mint a fresh 1-hour Cognito ID token and save it as $ID_TOKEN.
# SOURCE it (don't bash it) so the new token lands in your current shell:
#     source ~/environment/dev-on-aws/refresh-token.sh            # alice
#     source ~/environment/dev-on-aws/refresh-token.sh bob@example.com
# Needs $CLIENT_ID from Lab 6a (or bootstrap.sh 6a+). ID tokens expire after
# 60 minutes, so run this at the start of every lab from 6c onward.
source ~/.dev-on-aws.env
_who="${1:-alice@example.com}"
_tok=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH \
  --client-id "$CLIENT_ID" \
  --auth-parameters "USERNAME=$_who,PASSWORD=Tr0picalStorm!" \
  --query AuthenticationResult.IdToken --output text)
if [ -n "$_tok" ] && [ "$_tok" != "None" ]; then
  sed -i.bak '/^export ID_TOKEN=/d' ~/.dev-on-aws.env && rm -f ~/.dev-on-aws.env.bak
  echo "export ID_TOKEN=$_tok" >> ~/.dev-on-aws.env
  export ID_TOKEN="$_tok"
  echo "ID_TOKEN refreshed for $_who (valid 60 min)"
else
  echo "token refresh FAILED for $_who — check \$CLIENT_ID and the user's password" >&2
fi
unset _who _tok
