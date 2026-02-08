FROM python:3.9-slim

WORKDIR /app

# Copier les fichiers requirements
COPY requirements.txt .

# Installer les dépendances
RUN pip install --no-cache-dir -r requirements.txt

# Copier le code de l'application
COPY . .

# Exposer le port
EXPOSE 8080

# Commande de démarrage
CMD ["python", "-m", "addrservice.tornado.server", "-c", "/app/configs/addressbook-local.yaml"]
