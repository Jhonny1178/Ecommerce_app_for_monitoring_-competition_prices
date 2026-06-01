# Etap 1: Budowanie aplikacji Flutter Web
FROM ghcr.io/cirruslabs/flutter:3.22.2 AS build

WORKDIR /app

# Kopiowanie zależności i ich pobieranie
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Kopiowanie reszty kodu
COPY . .

# Budowanie wersji web
RUN flutter build web --release

# Etap 2: Serwowanie zbudowanej aplikacji przez Nginx
FROM nginx:alpine

# Usunięcie domyślnej strony startowej Nginxa
RUN rm -rf /usr/share/nginx/html/*

# Skopiowanie zbudowanych plików Flutter Web z poprzedniego etapu
COPY --from=build /app/build/web /usr/share/nginx/html

# Podmiana domyślnego pliku konfiguracyjnego Nginxa
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
