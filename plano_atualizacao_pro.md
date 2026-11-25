# Plano de Atualização - Plantão Operacional PRO

## 1. Persistência de Login
**Problema:** O usuário precisa fazer login a cada vez que abre o aplicativo.
**Solução:**
- Analisar `auth_service.dart` para verificar o uso de `signInSilently` e o gerenciamento de estado de inicialização.
- Garantir que o Firebase Auth restaure a sessão local sem depender apenas do `GoogleSignIn`.
- Corrigir a lógica de verificação inicial no `_AppRoot` em `main.dart` para aguardar a recuperação do usuário.

## 2. Escalas Automáticas (Gerador)
**Problema:** Opções 12x24 e 12x48 devem ser removidas; salvar no Google Calendar diretamente está causando erro.
**Solução:**
- Editar `schedule_generator_screen.dart` e remover as opções `12x24` e `12x48` da lista de escalas.
- Modificar a ação "Publicar": Em vez de chamar o Google Calendar diretamente, salvar a escala gerada no Hive (`commitments`).
- Adicionar um botão/ação opcional para "Sincronizar com Google Agenda" que pegue os compromissos locais da escala e envie para o Google, informando o progresso adequadamente.

## 3. Compartilhamento PRO (Criação de Grupos)
**Problema:** Ao nomear e concluir a criação de um grupo, ele não é criado.
**Solução:**
- Analisar `sharing_service.dart` e a interface correspondente.
- Verificar a comunicação com o Firebase Firestore ao criar um grupo.
- Adicionar tratamento de erros e certificar-se de que as permissões (Regras de Segurança do Firebase) permitem a criação, ou corrigir o modelo de dados enviado ao Firestore.

## 4. Sincronização Bidirecional com Google Agenda e Espelhamento Local
**Problema:** O calendário local precisa importar do Google Agenda e exportar em tempo real, além de compartilhar com os grupos.
**Solução:**
- Analisar `calendar_service.dart`.
- Implementar função de `importação` dos eventos do Google Calendar para a base local (Hive) no momento de inicialização ou login.
- Assegurar que ao adicionar um novo evento no app, ele seja:
  1. Salvo localmente (Hive).
  2. Salvo no Google Calendar.
  3. Propagado para o Firebase (se pertencer a um grupo).
- Configurar *listeners* no Firestore para atualização em tempo real na interface da agenda.
