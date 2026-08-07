# Armazém Pro Mobile 2.0

Aplicativo Android com interface adaptada para celular que abre o sistema oficial:

`https://armazempro.com.br/sistema/`

## Mesmo sistema do PC

O aplicativo **não cria um estoque separado**. Ele acessa o mesmo Armazém Pro online usado no computador. Assim, quando o usuário entra com a mesma conta/empresa, os dados continuam sendo lidos e gravados pelo sistema/Supabase atual.

Exemplo:
- registrar uma entrada no celular -> aparece no PC;
- registrar uma saída no PC -> aparece no celular após sincronização/atualização;
- produtos, estoque, kits, armazéns e movimentações permanecem na mesma base online.

## Melhorias para celular

- Barra superior mostrando que está online e usando o mesmo estoque do PC;
- Botões grandes: Voltar, Início e Atualizar;
- Gestos de atualizar;
- WebView com viewport e ajustes para formulários/tabelas em telas menores;
- Upload de arquivos;
- Downloads;
- Cookies/sessão de login;
- Tela sem internet;
- HTTPS obrigatório;
- Target SDK 36;
- Ícones e materiais da Play Store incluídos.

## Gerar APK sem celular

O projeto inclui GitHub Actions em `.github/workflows/build-android.yml`.
Ao publicar este projeto em um repositório GitHub na branch `main`, a ação gera automaticamente:

- `ARMAZEM-PRO-APK-INSTALAVEL` -> APK de teste instalável;
- `ARMAZEM-PRO-AAB` -> pacote para preparar a publicação na Play Store.

Também é possível abrir no Android Studio e gerar o APK pelo computador/emulador.

## Endereço do sistema

O endereço fica em `app/build.gradle.kts`, no campo `APP_URL`.
