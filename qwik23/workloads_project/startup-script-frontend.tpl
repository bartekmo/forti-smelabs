apt update
apt install -y nginx
echo "server { \
  listen 80;\
  proxy_connect_timeout 7;\
  location / { \
    proxy_pass http://10.0.2.2;\
  }\
}" > /etc/nginx/sites-available/proxy
rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/proxy /etc/nginx/sites-enabled/
systemctl restart nginx
