def dopasuj_cene(liczby):
    # obliczanie sredniej arytmetycznej
    srednia = sum(liczby) / len(liczby)

    # znalezienie liczby z listy najblizszej sredniej
    najblizsza = min(liczby, key=lambda x: abs(x - srednia))

    # interpolacja
    if najblizsza <= 20:
        odjac = (najblizsza / 20) * 1
    elif najblizsza <= 100:
        odjac = 1 + ((najblizsza - 20) / (100 - 20)) * (5 - 1)
    elif najblizsza <= 1000:
        odjac = 5 + ((najblizsza - 100) / (1000 - 100)) * (20 - 5)
    elif najblizsza <= 5000:
        odjac = 20 + ((najblizsza - 1000) / (5000 - 1000)) * (200 - 20)
    else:
        odjac = 200

    zmniejszona = najblizsza - odjac
    zmniejszona = max(0, zmniejszona)

    # zabezpieczenie przed zbytnim zblizeniem do mniejszej liczby
    mniejsze_liczby = [x for x in liczby if x < najblizsza]
    if mniejsze_liczby:
        najblizsza_mniejsza = max(mniejsze_liczby)
        dystans_do_mniejszej = abs(zmniejszona - najblizsza_mniejsza)
        dystans_do_bazowej = abs(najblizsza - zmniejszona)

        if dystans_do_mniejszej < dystans_do_bazowej:
            zmniejszona = najblizsza

    # zaokraglanie i odejmowanie koncowek
    if zmniejszona < 100:
        zmniejszona = round(zmniejszona)
        wynik = zmniejszona - 0.01
    elif zmniejszona < 1000:
        zmniejszona = round(zmniejszona, -1)
        wynik = zmniejszona - 1
    else:
        wynik = zmniejszona

    return round(wynik, 2)


def ustal_cene(liczby, nasza_cena):
    # jesli lista jest pusta +20%
    if not liczby:
        nowa_cena = nasza_cena * 1.20
        return round(nowa_cena, 2)
    else:
        return dopasuj_cene(liczby)
