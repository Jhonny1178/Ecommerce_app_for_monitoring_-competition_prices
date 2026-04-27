from flask import Flask, render_template, jsonify
import algorytm
import llm

app = Flask(__name__)

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/pobierz_dane')
def pobierz_dane():
    # Przekazuje dane z algorytm.py do Frontendu
    return jsonify({
        "nasz_produkt": algorytm.nasz_produkt,
        "konkurencja": algorytm.konkurencja,
        "cena_algorytmu": algorytm.final_price
    })

@app.route('/rekomenduj')
def rekomenduj():
    # Uruchamia funkcję LLM z Twojego pliku
    wynik = llm.zapytaj_ai_o_cene(
        algorytm.cena_producenta, algorytm.cena_hurtowa,
        algorytm.stan_magazynu, algorytm.konkurencja,
        algorytm.srednia_cena, algorytm.final_price
    )
    return jsonify(wynik)

if __name__ == '__main__':
    app.run(debug=True)