FROM dart:3.13.5-sdk AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/server /app/server
COPY migrations /app/migrations
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
