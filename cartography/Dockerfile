FROM python:3.14-slim
WORKDIR /app
COPY server.py style.json ./
COPY tools/build_style.py ./tools/build_style.py
COPY assets ./assets
COPY data ./data
EXPOSE 8765
USER 65534:65534
ENTRYPOINT ["python", "server.py", "--host", "0.0.0.0"]
