/// Frases de trabalho totalmente locais: independem de internet e ML Kit.
/// São traduções pré-definidas, NÃO tradução de qualquer fala.
class WorkPhrase {
  const WorkPhrase({
    required this.id,
    required this.category,
    required this.pt,
    required this.en,
    this.priority = false,
  });
  final String id;
  final String category;
  final String pt;
  final String en;
  final bool priority;
}

const workCategories = <String>[
  'Todos', 'Segurança', 'Manutenção', 'Logística', 'Atendimento', 'Conversa',
];

const workPhrases = <WorkPhrase>[
  WorkPhrase(id: 'stop', category: 'Segurança', pt: 'Pare a máquina imediatamente.', en: 'Stop the machine immediately.', priority: true),
  WorkPhrase(id: 'danger', category: 'Segurança', pt: 'Há um risco de acidente aqui.', en: 'There is a safety hazard here.', priority: true),
  WorkPhrase(id: 'ppe', category: 'Segurança', pt: 'É obrigatório usar equipamento de proteção.', en: 'You must wear protective equipment.'),
  WorkPhrase(id: 'emergency', category: 'Segurança', pt: 'Precisamos de ajuda imediatamente.', en: 'We need help immediately.', priority: true),
  WorkPhrase(id: 'wait', category: 'Segurança', pt: 'Espere, não toque nesse equipamento.', en: 'Wait, do not touch that equipment.', priority: true),
  WorkPhrase(id: 'check', category: 'Manutenção', pt: 'Pode verificar se o equipamento está funcionando?', en: 'Can you check if the equipment is working?'),
  WorkPhrase(id: 'power', category: 'Manutenção', pt: 'Desligue a energia antes de fazer a manutenção.', en: 'Turn off the power before performing maintenance.', priority: true),
  WorkPhrase(id: 'broken', category: 'Manutenção', pt: 'O equipamento está com defeito.', en: 'The equipment is malfunctioning.'),
  WorkPhrase(id: 'test', category: 'Manutenção', pt: 'Vamos testar o equipamento.', en: 'Let us test the equipment.'),
  WorkPhrase(id: 'part', category: 'Manutenção', pt: 'Precisamos substituir esta peça.', en: 'We need to replace this part.'),
  WorkPhrase(id: 'delivery', category: 'Logística', pt: 'Onde devo entregar o material?', en: 'Where should I deliver the material?'),
  WorkPhrase(id: 'truck', category: 'Logística', pt: 'O caminhão chegou para descarregar.', en: 'The truck has arrived for unloading.'),
  WorkPhrase(id: 'quantity', category: 'Logística', pt: 'Precisamos confirmar a quantidade.', en: 'We need to confirm the quantity.'),
  WorkPhrase(id: 'location', category: 'Logística', pt: 'Onde fica o depósito?', en: 'Where is the warehouse?'),
  WorkPhrase(id: 'help', category: 'Atendimento', pt: 'Como posso ajudar?', en: 'How can I help you?'),
  WorkPhrase(id: 'repeat', category: 'Atendimento', pt: 'Pode repetir mais devagar, por favor?', en: 'Could you repeat that more slowly, please?'),
  WorkPhrase(id: 'moment', category: 'Atendimento', pt: 'Um momento, por favor.', en: 'One moment, please.'),
  WorkPhrase(id: 'understand', category: 'Conversa', pt: 'Eu estou usando um tradutor para conversar.', en: 'I am using a translator to communicate.'),
  WorkPhrase(id: 'thanks', category: 'Conversa', pt: 'Obrigado pela ajuda.', en: 'Thank you for your help.'),
  WorkPhrase(id: 'name', category: 'Conversa', pt: 'Qual é o seu nome?', en: 'What is your name?'),
];

List<WorkPhrase> findWorkPhrases(String query, {String category = 'Todos'}) {
  final term = query.trim().toLowerCase();
  return workPhrases.where((phrase) {
    if (category != 'Todos' && phrase.category != category) return false;
    if (term.isEmpty) return true;
    return phrase.pt.toLowerCase().contains(term) ||
        phrase.en.toLowerCase().contains(term) ||
        phrase.category.toLowerCase().contains(term);
  }).toList(growable: false);
}
