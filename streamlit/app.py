# PDF Worker — Streamlit App (Responsive Grid Version)
import streamlit as st
import pikepdf
from PIL import Image

# --- Page setup ---
st.set_page_config(page_title="PDF Worker", page_icon="📄", layout="wide")

# --- Animated minimalistic background + responsive grid styling ---
st.markdown(
    """
    <style>
    @keyframes gradientShift {
        0% {background-position: 0% 50%;}
        50% {background-position: 100% 50%;}
        100% {background-position: 0% 50%;}
    }
    body {
        background: linear-gradient(-45deg, #f8f9fa, #e9ecef, #f1f3f5, #dee2e6);
        background-size: 400% 400%;
        animation: gradientShift 20s ease infinite;
        font-family: 'Inter', sans-serif;
        color: #333333;
        transition: background-position 0.2s ease;
    }
    h1, h2, h3 {
        color: #222222;
        font-weight: 600;
    }
    .stButton>button {
        background-color: #333333;
        color: white;
        border-radius: 6px;
        padding: 0.5em 1.2em;
        font-weight: 500;
    }
    .stButton>button:hover {
        background-color: #555555;
    }
    .stFileUploader {
        border: 1px solid #dddddd;
        border-radius: 6px;
        padding: 0.5em;
        background-color: #ffffff;
    }

    /* Responsive grid layout */
    .tool-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 1.5rem;
        margin-top: 1rem;
    }
    .tool-box {
        background-color: #ffffffcc;
        border-radius: 10px;
        padding: 1.2rem;
        box-shadow: 0 0 10px rgba(0,0,0,0.05);
        transition: transform 0.2s ease;
    }
    .tool-box:hover {
        transform: translateY(-3px);
    }
    @media (max-width: 900px) {
        .tool-grid { grid-template-columns: 1fr 1fr; }
    }
    @media (max-width: 600px) {
        .tool-grid { grid-template-columns: 1fr; }
    }
    </style>

    <script>
    document.addEventListener('mousemove', function(e) {
        const x = e.clientX / window.innerWidth;
        const y = e.clientY / window.innerHeight;
        document.body.style.backgroundPosition = `${x*100}% ${y*100}%`;
    });
    </script>
    """,
    unsafe_allow_html=True
)

# --- App title ---
st.title("📄 PDF Worker")

# --- Responsive grid container ---
st.markdown("<div class='tool-grid'>", unsafe_allow_html=True)

# --- Merge PDFs ---
st.markdown("<div class='tool-box'>", unsafe_allow_html=True)
st.subheader("📑 Merge PDFs")
uploaded_files = st.file_uploader("Upload PDFs to merge", type="pdf", accept_multiple_files=True)
if st.button("Merge PDFs"):
    if uploaded_files:
        merged = pikepdf.Pdf.new()
        for f in uploaded_files:
            pdf = pikepdf.Pdf.open(f)
            merged.pages.extend(pdf.pages)
        merged.save("merged.pdf")
        st.success("Merged successfully!")
        st.download_button("Download merged PDF", open("merged.pdf", "rb"), "merged.pdf")
    else:
        st.warning("Please upload at least one PDF.")
st.markdown("</div>", unsafe_allow_html=True)

# --- Compress PDF ---
st.markdown("<div class='tool-box'>", unsafe_allow_html=True)
st.subheader("🪶 Compress PDF")
compress_file = st.file_uploader("Upload a PDF to compress", type="pdf")
if st.button("Compress PDF"):
    if compress_file:
        pdf = pikepdf.open(compress_file)
        pdf.save("compressed.pdf", optimize_version=True)
        st.success("PDF compressed successfully!")
        st.download_button("Download compressed PDF", open("compressed.pdf", "rb"), "compressed.pdf")
    else:
        st.warning("Please upload a PDF to compress.")
st.markdown("</div>", unsafe_allow_html=True)

# --- Image to PDF Converter ---
st.markdown("<div class='tool-box'>", unsafe_allow_html=True)
st.subheader("🖼️ Image to PDF Converter")
image_files = st.file_uploader("Upload images to convert", type=["jpg", "jpeg", "png"], accept_multiple_files=True)
if st.button("Convert Images to PDF"):
    if image_files:
        images = [Image.open(img).convert("RGB") for img in image_files]
        images[0].save("images.pdf", save_all=True, append_images=images[1:])
        st.success("Images converted successfully!")
        st.download_button("Download PDF", open("images.pdf", "rb"), "images.pdf")
    else:
        st.warning("Please upload at least one image.")
st.markdown("</div>", unsafe_allow_html=True)

# --- Split & Insert PDF ---
st.markdown("<div class='tool-box'>", unsafe_allow_html=True)
st.subheader("✂️ Split & Insert PDF")
split_pdf = st.file_uploader("Upload a PDF to split", type="pdf")
insert_pdf = st.file_uploader("Upload another PDF to insert", type="pdf")
start_page = st.number_input("Start page to split (1‑indexed)", min_value=1, step=1)
end_page = st.number_input("End page to split (inclusive)", min_value=1, step=1)
if st.button("Split and Insert"):
    if split_pdf and insert_pdf:
        base = pikepdf.Pdf.open(split_pdf)
        insert = pikepdf.Pdf.open(insert_pdf)
        part1 = base.pages[:start_page - 1]
        part2 = base.pages[end_page:]
        new_pdf = pikepdf.Pdf.new()
        new_pdf.pages.extend(part1)
        new_pdf.pages.extend(insert.pages)
        new_pdf.pages.extend(part2)
        new_pdf.save("modified.pdf")
        st.success("PDF split and insertion completed!")
        st.download_button("Download modified PDF", open("modified.pdf", "rb"), "modified.pdf")
    else:
        st.warning("Please upload both PDFs and specify page range.")
st.markdown("</div>", unsafe_allow_html=True)

# --- Close grid container ---
st.markdown("</div>", unsafe_allow_html=True)

# --- Footer ---
st.markdown(
    """
    ---
    <p style='text-align:center; color:#555555;'>
    Developed by <b>Prabhat Baskota</b> · © 2026 · Built with Streamlit, PikePDF & Pillow
    </p>
    """,
    unsafe_allow_html=True
)
