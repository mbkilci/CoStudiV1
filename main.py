import platform
import subprocess # LibreOffice'i çağırmak için
from pdf2docx import Converter # PDF -> DOCX için
import tempfile # Geçici dosya işlemleri için
import shutil
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware  # <-- YENİ EKLENTİ
from typing import List
from PIL import Image
from pypdf import PdfWriter, PdfReader
import io
import os
from fastapi.responses import StreamingResponse, JSONResponse
# --- HEALTH CHECK (RENDER İÇİN ŞART) ---
@app.get("/")
def read_root():
    return {"message": "CoStudi API is running!"}

def get_libreoffice_command():
    # İşletim sistemini kontrol et
    if platform.system() == "Darwin": # macOS
        return "/Applications/LibreOffice.app/Contents/MacOS/soffice"
    else: # Linux (Docker/Render)
        return "libreoffice"

app = FastAPI(title="Costudi API", version="1.0")

# --- CORS AYARLARI (WEB İÇİN ZORUNLU) ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Tüm sitelere izin ver (Geliştirme aşaması için)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {"message": "Costudi Backend (Web Ready) 🚀"}

# --- 1. RESİM İŞLEMLERİ ---
@app.post("/image-process/")
async def process_image(
    file: UploadFile = File(...), 
    format: str = Form("png"),
    quality: int = Form(100),
    resize_ratio: float = Form(1.0)
):
    try:
        image_data = await file.read()
        image = Image.open(io.BytesIO(image_data))
        
        target_format = format.upper()
        if target_format in ["JPG", "JPEG"]:
            target_format = "JPEG"
            if image.mode == "RGBA": image = image.convert("RGB")
        elif target_format == "PDF" and image.mode == "RGBA":
            image = image.convert("RGB")

        if resize_ratio < 1.0:
            new_width = int(image.width * resize_ratio)
            new_height = int(image.height * resize_ratio)
            image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)

        output_buffer = io.BytesIO()
        save_params = {}
        if target_format == "JPEG": save_params["quality"] = quality
            
        image.save(output_buffer, format=target_format, **save_params)
        output_buffer.seek(0)
        
        filename = f"costudi_processed.{format.lower()}"
        media_type = "application/pdf" if target_format == "PDF" else f"image/{format.lower()}"
        
        return StreamingResponse(
            output_buffer, 
            media_type=media_type, 
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})

# --- 2. AKILLI BİRLEŞTİRME (PDF + RESİM + OFFICE) ---
@app.post("/pdf-merge/")
async def merge_pdfs(files: List[UploadFile] = File(...)):
    try:
        merger = PdfWriter()
        temp_files_to_clean = [] # İşlem bitince silinecek geçici dosyalar

        for file in files:
            filename = file.filename.lower()
            file_content = await file.read()
            file_buffer = io.BytesIO(file_content)

            # 1. DURUM: OFFICE DOSYASI (DOCX / PPTX)
            if filename.endswith(('.docx', '.pptx', '.doc', '.ppt')):
                # Geçici olarak kaydet
                ext = os.path.splitext(filename)[1]
                with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp_office:
                    tmp_office.write(file_content)
                    tmp_office_path = tmp_office.name
                    temp_files_to_clean.append(tmp_office_path)

                # Çıktı klasörü
                output_dir = tempfile.mkdtemp()
                temp_files_to_clean.append(output_dir) # Klasörü de not et

                # LibreOffice ile PDF'e çevir
                soffice_path = get_libreoffice_command()
                if os.path.exists(soffice_path):
                    subprocess.run([
                        soffice_path, 
                        '--headless', 
                        '--convert-to', 'pdf', 
                        '--outdir', output_dir, 
                        tmp_office_path
                    ], check=True)
                    
                    # Oluşan PDF'i bul ve oku
                    filename_no_ext = os.path.splitext(os.path.basename(tmp_office_path))[0]
                    converted_pdf_path = os.path.join(output_dir, f"{filename_no_ext}.pdf")
                    
                    if os.path.exists(converted_pdf_path):
                        merger.append(PdfReader(converted_pdf_path))
                        temp_files_to_clean.append(converted_pdf_path)
                else:
                    print("LibreOffice bulunamadı, bu dosya atlanıyor.")

            # 2. DURUM: RESİM (JPG / PNG)
            elif filename.endswith(('.png', '.jpg', '.jpeg', '.webp')):
                image = Image.open(file_buffer)
                if image.mode == "RGBA":
                    image = image.convert("RGB")
                
                img_pdf_buffer = io.BytesIO()
                image.save(img_pdf_buffer, format="PDF")
                img_pdf_buffer.seek(0)
                merger.append(PdfReader(img_pdf_buffer))

            # 3. DURUM: ZATEN PDF
            else:
                merger.append(PdfReader(file_buffer))

        # Sonuç PDF'ini oluştur
        output_buffer = io.BytesIO()
        merger.write(output_buffer)
        merger.close()
        output_buffer.seek(0)

        # Temizlik (Geçici dosyaları sil)
        for path in temp_files_to_clean:
            try:
                if os.path.isdir(path):
                    shutil.rmtree(path, ignore_errors=True)
                elif os.path.isfile(path):
                    os.remove(path)
            except:
                pass

        return StreamingResponse(
            output_buffer, 
            media_type="application/pdf",
            headers={"Content-Disposition": "attachment; filename=costudi_merged.pdf"}
        )

    except Exception as e:
        print(f"MERGE HATASI: {e}")
        return JSONResponse(status_code=500, content={"error": str(e)})
# --- 3. PDF AYIKLAMA ---
@app.post("/pdf-extract/")
async def extract_pdf_pages(
    file: UploadFile = File(...),
    selected_pages: str = Form(...)
):
    try:
        file_content = io.BytesIO(await file.read())
        reader = PdfReader(file_content)
        writer = PdfWriter()
        page_indices = [int(p.strip()) for p in selected_pages.split(",") if p.strip().isdigit()]
        
        for i in page_indices:
            if i < len(reader.pages):
                writer.add_page(reader.pages[i])
        
        output_buffer = io.BytesIO()
        writer.write(output_buffer)
        output_buffer.seek(0)
        
        return StreamingResponse(
            output_buffer, 
            media_type="application/pdf",
            headers={"Content-Disposition": "attachment; filename=costudi_extracted.pdf"}
        )
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
    # --- 4. OFFICE (DOCX/PPTX) -> PDF ---
@app.post("/office-to-pdf/")
async def office_to_pdf(file: UploadFile = File(...)):
    try:
        # 1. Dosyayı geçici olarak kaydet
        input_ext = os.path.splitext(file.filename)[1]
        with tempfile.NamedTemporaryFile(delete=False, suffix=input_ext) as tmp_input:
            tmp_input.write(await file.read())
            tmp_input_path = tmp_input.name

        # 2. Çıktı klasörü oluştur
        output_dir = tempfile.mkdtemp()
        
        # 3. LibreOffice Komutu (Mac için özel yol)
        # Eğer LibreOffice Applications içinde ise yol genelde budur:
        soffice_path = get_libreoffice_command()
        if not os.path.exists(soffice_path):
            return JSONResponse(status_code=500, content={"error": "LibreOffice bulunamadı. Lütfen kurun."})

        subprocess.run([
            soffice_path, 
            '--headless', 
            '--convert-to', 'pdf', 
            '--outdir', output_dir, 
            tmp_input_path
        ], check=True)

        # 4. Oluşan PDF'i bul
        filename_no_ext = os.path.splitext(os.path.basename(tmp_input_path))[0]
        output_pdf_path = os.path.join(output_dir, f"{filename_no_ext}.pdf")

        # 5. Dosyayı oku ve temizle
        with open(output_pdf_path, "rb") as f:
            pdf_data = f.read()

        # Temizlik
        os.remove(tmp_input_path)
        shutil.rmtree(output_dir)

        return StreamingResponse(
            io.BytesIO(pdf_data), 
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={file.filename}.pdf"}
        )

    except subprocess.CalledProcessError as e:
        return JSONResponse(status_code=500, content={"error": f"Dönüştürme Hatası: {str(e)}"})
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})


# --- 5. PDF -> DOCX (WORD) - GÜVENLİ GERİ DÖNÜŞ ---
@app.post("/pdf-to-docx/")
async def pdf_to_docx(file: UploadFile = File(...)):
    try:
        # 1. PDF'i kaydet
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp_pdf:
            tmp_pdf.write(await file.read())
            tmp_pdf_path = tmp_pdf.name

        # 2. DOCX dosyası için yol belirle
        tmp_docx_path = tmp_pdf_path.replace(".pdf", ".docx")

        # 3. Dönüştür
        # Not: multi_processing=False sunucu çökmesini engeller
        cv = Converter(tmp_pdf_path)
        
        # Tabloları daha iyi yakalaması için varsayılan ayarları kullanıyoruz.
        # pdf2docx, tabloları çizgilerine (border) göre tanır.
        cv.convert(tmp_docx_path, start=0, end=None, multi_processing=False)
        cv.close()

        # 4. Veriyi oku
        with open(tmp_docx_path, "rb") as f:
            docx_data = f.read()

        # Temizlik
        os.remove(tmp_pdf_path)
        os.remove(tmp_docx_path)

        return StreamingResponse(
            io.BytesIO(docx_data), 
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            headers={"Content-Disposition": "attachment; filename=converted.docx"}
        )
    except Exception as e:
        print(f"HATA: {str(e)}") # Terminalde hatayı görelim
        return JSONResponse(status_code=500, content={"error": str(e)})