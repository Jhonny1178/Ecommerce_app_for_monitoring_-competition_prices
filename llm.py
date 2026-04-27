import json
import os
from groq import Groq

# IMPORT DANYCH Z PLIKU algorytm.py
from algorytm import (
    cena_producenta,
    cena_hurtowa,
    stan_magazynu,
    konkurencja,
    srednia_cena,
    final_price
)

API_KEY = os.getenv("GROQ_API_KEY")
client = Groq(api_key=API_KEY)


def zapytaj_ai_o_cene(cena_producenta, cena_hurtowa, stan_magazynu, pelna_konkurencja, srednia_cena, final_price):
    system_prompt = """
        Jesteś dyrektorem handlowym i wybitnym ekspertem ds. pricingu. Otrzymujesz surowe dane rynkowe i masz absolutnie wolną rękę w ustaleniu ostatecznej ceny produktu. Nie narzucam Ci żadnego algorytmu.

        Twoje cele:
        1. Maksymalizacja zysku i mądre zarządzanie rotacją towaru.
        2. Wykorzystywanie słabości konkurencji (np. ich braków magazynowych).
        3. Stosowanie psychologii cen (np. końcówki .99, .90).

        JEDYNY ZAKAZ (KRYTYCZNE):
        Nigdy, pod żadnym pozorem nie proponuj ceny niższej niż {cena_hurtowa} PLN. To nasze dno opłacalności. Jeśli zejdziesz poniżej, zbankrutujemy.

        Wymagany format JSON. Myśl jak rasowy handlowiec:
        {
          "analiza_sytuacji": "Zwięźle oceń rynek na podstawie danych",
          "strategia": "Jaką rynkową strategię przyjmujesz i dlaczego",
          "nowa_cena": liczba,
          "argumentacja": "Dlaczego ta konkretna kwota jest najlepsza"
        }
        """

    user_prompt = f"""
    Dane wejściowe:
    - Cena producenta: {cena_producenta} PLN
    - Cena hurtowa: {cena_hurtowa} PLN
    - Nasz stan magazynowy: {stan_magazynu} szt.
    - Pełny obraz konkurencji (cena i dostępność): {pelna_konkurencja}
    - Średnia cena aktywnych konkurentów: {srednia_cena} PLN
    - Wyliczona cena przez algorytm: {final_price} PLN
    """

    try:
        response = client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.2,
            response_format={"type": "json_object"}
        )

        return json.loads(response.choices[0].message.content)

    except Exception as e:
        print(f"Błąd API: {e}")
        return None


if __name__ == "__main__":
    print(f"Pobrana cena z algorytmu: {final_price:.2f} PLN")
    print("Wysyłam zapytanie do AI w celu weryfikacji...\n")

    wynik_ai = zapytaj_ai_o_cene(
        cena_producenta=cena_producenta,
        cena_hurtowa=cena_hurtowa,
        stan_magazynu=stan_magazynu,
        pelna_konkurencja=konkurencja,
        srednia_cena=srednia_cena,
        final_price=final_price
    )

    if wynik_ai:
        print(f"Rekomendacja AI (Nowa cena): {wynik_ai['nowa_cena']} PLN")
        print(f"Argumentacja AI: {wynik_ai['argumentacja']}")