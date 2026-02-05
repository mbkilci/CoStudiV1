# Python 3.9 kullan
FROM python:3.9-slim

# Sistemi güncelle ve LibreOffice'i kur (Linux versiyonu)
RUN apt-get update && apt-get install -y \
    libreoffice \
    default-jre \
    libreoffice-java-common \
    && apt-get clean

# Çalışma klasörünü ayarla
WORKDIR /app

# Kütüphaneleri yükle
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Tüm kodları kopyala
COPY . .

# Portu aç ve başlat
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]