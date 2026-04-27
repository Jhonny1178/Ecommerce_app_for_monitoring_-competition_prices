nasz_produkt = {"cena_producenta": 850, "cena_hurtowa": 600, "stan_magazynu": 5}

konkurencja1 = {"cena": 840, "stan_magazynu": True}
konkurencja2 = {"cena": 860, "stan_magazynu": False}
konkurencja3 = {"cena": 899, "stan_magazynu": True}
konkurencja = [konkurencja1, konkurencja2, konkurencja3]

cena_producenta = nasz_produkt["cena_producenta"]
cena_hurtowa = nasz_produkt["cena_hurtowa"]
stan_magazynu = nasz_produkt["stan_magazynu"]


def magazyn_konkurencji(lista_sklepow):
    return [sklep for sklep in lista_sklepow if sklep["stan_magazynu"] != False]


aktywna_konkurencja = magazyn_konkurencji(konkurencja)

if len(aktywna_konkurencja) > 0:
    srednia_cena = sum(sklep["cena"] for sklep in aktywna_konkurencja) / len(aktywna_konkurencja)
    najtanszy_konkurent = min(sklep["cena"] for sklep in aktywna_konkurencja)
else:
    srednia_cena = cena_producenta
    najtanszy_konkurent = cena_producenta


def procent_bezpieczenstwa(cena_bazowa):
    if cena_bazowa < 300:
        return 0.4
    elif cena_bazowa < 1000:
        return 0.3
    elif cena_bazowa < 2000:
        return 0.2
    else:
        return 0.1


def minimalna_cena(cena_producenta, cena_hurtowa):
    min_marza = cena_hurtowa * (1 + procent_bezpieczenstwa(cena_hurtowa))
    if cena_producenta > min_marza:
        min_cena = cena_producenta
    else:
        min_cena = min_marza
    return min_cena


def maksymalna_cena(srednia_cena):
    procent = procent_bezpieczenstwa(srednia_cena)
    return srednia_cena * (1 + procent)


def warunek_magazynowy(stan_magazynu, srednia_cena, aktywna_konkurencja, standardowa_cena):
    if stan_magazynu <= 3 and len(aktywna_konkurencja) > 0:
        return srednia_cena * 1.1
    elif len(aktywna_konkurencja) == 0:
        return maksymalna_cena(srednia_cena)
    else:
        return standardowa_cena


def cena_ostateczna(najtanszy_konkurent, cena_producenta, cena_hurtowa, stan_magazynu, srednia_cena,
                    aktywna_konkurencja):
    proponowana_cena = najtanszy_konkurent - 10

    min_cena = minimalna_cena(cena_producenta, cena_hurtowa)
    if proponowana_cena < min_cena:
        proponowana_cena = min_cena

    ostateczny_wynik = warunek_magazynowy(stan_magazynu, srednia_cena, aktywna_konkurencja, proponowana_cena)
    return ostateczny_wynik


final_price = cena_ostateczna(najtanszy_konkurent, cena_producenta, cena_hurtowa, stan_magazynu, srednia_cena,
                              aktywna_konkurencja)

# Zabezpieczenie przed podwójnym printowaniem przy imporcie
if __name__ == "__main__":
    print(final_price)