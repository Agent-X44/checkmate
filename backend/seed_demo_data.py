"""
Demo Seeding Script for CheckMate LMS.
Populates the database with 15 dummy students.
"""
import os
import uuid
from supabase import create_client
from dotenv import load_dotenv

load_dotenv()

# Configuration
URL = os.getenv("SUPABASE_URL")
KEY = os.getenv("SUPABASE_KEY")
supabase = create_client(URL, KEY)

DEMO_CLASS_ID = "PASTE_YOUR_CLASS_ID_HERE"

STUDENTS = [
    {"name": "Alice Johnson", "email": "alice@example.com"},
    {"name": "Bob Smith", "email": "bob@example.com"},
    {"name": "Charlie Brown", "email": "charlie@example.com"},
    {"name": "Diana Prince", "email": "diana@example.com"},
    {"name": "Ethan Hunt", "email": "ethan@example.com"},
    {"name": "Fiona Gallagher", "email": "fiona@example.com"},
    {"name": "George Miller", "email": "george@example.com"},
    {"name": "Hannah Abbott", "email": "hannah@example.com"},
    {"name": "Ian Wright", "email": "ian@example.com"},
    {"name": "Jenny Forrest", "email": "jenny@example.com"},
    {"name": "Kevin Hart", "email": "kevin@example.com"},
    {"name": "Laura Croft", "email": "laura@example.com"},
    {"name": "Mike Ross", "email": "mike@example.com"},
    {"name": "Nina Simone", "email": "nina@example.com"},
    {"name": "Oscar Wilde", "email": "oscar@example.com"},
]

def seed():
    print("Starting seed for Class ID:", DEMO_CLASS_ID)
    
    for s in STUDENTS:
        try:
            student_id = str(uuid.uuid4())
            
            supabase.table("profiles").insert({
                "id": student_id,
                "name": s["name"],
                "email": s["email"],
                "role": "Student"
            }).execute()
            
            supabase.table("enrollments").insert({
                "user_id": student_id,
                "class_id": DEMO_CLASS_ID,
                "role": "Student"
            }).execute()
            
            print("Enrolled:", s['name'])
            
        except Exception as e:
            print("Error seeding", s['name'], ":", e)

if __name__ == "__main__":
    if DEMO_CLASS_ID == "PASTE_YOUR_CLASS_ID_HERE":
        print("Error: Please paste a valid Class ID from your Supabase dashboard.")
    else:
        seed()
