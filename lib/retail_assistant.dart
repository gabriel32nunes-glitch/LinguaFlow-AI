/// Respostas de loja aprovadas pelo atendente, sem texto gerado por IA.
/// Nao promete preco, estoque, prazo ou desconto sem confirmacao humana.
class RetailReply {
  const RetailReply({
    required this.id,
    required this.category,
    required this.pt,
    required this.en,
  });

  final String id;
  final String category;
  final String pt;
  final String en;
}

const retailReplies = <RetailReply>[
  RetailReply(id: 'welcome', category: 'Recepção',
      pt: 'Olá! Como posso ajudar?', en: 'Hello! How can I help you?'),
  RetailReply(id: 'translator', category: 'Recepção',
      pt: 'Estou usando um tradutor para atender você melhor.',
      en: 'I am using a translator to assist you better.'),
  RetailReply(id: 'moment', category: 'Recepção',
      pt: 'Um momento, por favor.', en: 'One moment, please.'),
  RetailReply(id: 'repeat', category: 'Recepção',
      pt: 'Pode repetir mais devagar, por favor?',
      en: 'Could you repeat that more slowly, please?'),
  RetailReply(id: 'show_item', category: 'Produtos',
      pt: 'Pode me mostrar qual produto você procura?',
      en: 'Could you show me which product you are looking for?'),
  RetailReply(id: 'alternatives', category: 'Produtos',
      pt: 'Posso mostrar outras opções.',
      en: 'I can show you some other options.'),
  RetailReply(id: 'check_price', category: 'Preço',
      pt: 'Vou confirmar o preço para você.',
      en: 'I will check the price for you.'),
  RetailReply(id: 'price_tag', category: 'Preço',
      pt: 'Vou mostrar o preço na etiqueta.',
      en: 'I will show you the price on the tag.'),
  RetailReply(id: 'check_discount', category: 'Preço',
      pt: 'Vou verificar se existe algum desconto.',
      en: 'I will check if any discount is available.'),
  RetailReply(id: 'check_size', category: 'Tamanho',
      pt: 'Vou conferir se temos esse tamanho.',
      en: 'I will check whether we have that size.'),
  RetailReply(id: 'try_on', category: 'Tamanho',
      pt: 'Você gostaria de experimentar?',
      en: 'Would you like to try it on?'),
  RetailReply(id: 'check_color', category: 'Produtos',
      pt: 'Vou conferir as cores disponíveis.',
      en: 'I will check which colors are available.'),
  RetailReply(id: 'check_stock', category: 'Estoque',
      pt: 'Vou consultar nosso estoque.',
      en: 'I will check our stock.'),
  RetailReply(id: 'check_payment', category: 'Pagamento',
      pt: 'Vou confirmar se aceitamos cartão e outras formas de pagamento.',
      en: 'I will check whether we accept cards and other payment methods.'),
  RetailReply(id: 'receipt', category: 'Pagamento',
      pt: 'Você precisa de um comprovante?',
      en: 'Would you like a receipt?'),
  RetailReply(id: 'check_exchange', category: 'Trocas',
      pt: 'Vou verificar nossa política de trocas e devoluções.',
      en: 'I will check our exchange and return policy.'),
  RetailReply(id: 'check_delivery', category: 'Entrega',
      pt: 'Vou verificar as opções e os prazos de entrega.',
      en: 'I will check the delivery options and estimated times.'),
  RetailReply(id: 'ask_address', category: 'Entrega',
      pt: 'Qual é o endereço de entrega?',
      en: 'What is the delivery address?'),
  RetailReply(id: 'manager', category: 'Atendimento',
      pt: 'Vou chamar um responsável para ajudar.',
      en: 'I will ask a manager to help.'),
  RetailReply(id: 'anything_else', category: 'Atendimento',
      pt: 'Posso ajudar em mais alguma coisa?',
      en: 'Is there anything else I can help you with?'),
  RetailReply(id: 'thanks', category: 'Atendimento',
      pt: 'Muito obrigado! Tenha um ótimo dia.',
      en: 'Thank you very much! Have a great day.'),
];

const retailCategories = <String>[
  'Todos', 'Recepção', 'Produtos', 'Preço', 'Tamanho',
  'Estoque', 'Pagamento', 'Trocas', 'Entrega', 'Atendimento',
];

RetailReply? findRetailReply(String id) {
  for (final reply in retailReplies) {
    if (reply.id == id) return reply;
  }
  return null;
}

List<RetailReply> searchRetailReplies(String query, {String category = 'Todos'}) {
  final term = _normalize(query);
  return retailReplies.where((reply) {
    if (category != 'Todos' && category != reply.category) return false;
    if (term.isEmpty) return true;
    return _normalize(reply.pt).contains(term) ||
        _normalize(reply.en).contains(term) ||
        _normalize(reply.category).contains(term);
  }).toList(growable: false);
}

String _normalize(String value) {
  var result = value.toLowerCase();
  const accents = <String, String>{
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'ê': 'e', 'è': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'ç': 'c',
  };
  for (final accent in accents.entries) {
    result = result.replaceAll(accent.key, accent.value);
  }
  return result.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _hasAny(Set<String> words, List<String> keywords) =>
    keywords.any(words.contains);

/// Sugestoes baseadas apenas em palavras da fala reconhecida/traduzida.
/// Nao afirma compreender intencoes com IA nem inventa respostas comerciais.
List<RetailReply> suggestRetailReplies(String customerSpeech) {
  final words = _normalize(customerSpeech).split(' ').toSet();
  String? topic;
  if (_hasAny(words, ['price', 'cost', 'much', 'preco', 'valor', 'custa', 'quanto'])) {
    topic = 'Preço';
  } else if (_hasAny(words, ['discount', 'sale', 'desconto', 'promocao'])) {
    topic = 'Desconto';
  } else if (_hasAny(words, ['size', 'sizes', 'fit', 'tamanho', 'numero', 'provar', 'experimentar'])) {
    topic = 'Tamanho';
  } else if (_hasAny(words, ['color', 'colour', 'colors', 'cores', 'cor'])) {
    topic = 'Cor';
  } else if (_hasAny(words, ['card', 'cash', 'pay', 'payment', 'pix', 'cartao', 'dinheiro', 'pagar', 'pagamento'])) {
    topic = 'Pagamento';
  } else if (_hasAny(words, ['return', 'refund', 'exchange', 'troca', 'devolucao', 'devolver'])) {
    topic = 'Trocas';
  } else if (_hasAny(words, ['delivery', 'shipping', 'ship', 'entrega', 'frete', 'envio'])) {
    topic = 'Entrega';
  } else if (_hasAny(words, ['stock', 'available', 'availability', 'estoque', 'disponivel', 'tem'])) {
    topic = 'Estoque';
  }
  final ids = switch (topic) {
    'Preço' => ['check_price', 'price_tag', 'moment', 'anything_else'],
    'Desconto' => ['check_discount', 'moment', 'alternatives', 'anything_else'],
    'Tamanho' => ['check_size', 'try_on', 'moment', 'alternatives'],
    'Cor' => ['check_color', 'alternatives', 'moment', 'anything_else'],
    'Pagamento' => ['check_payment', 'receipt', 'moment', 'anything_else'],
    'Trocas' => ['check_exchange', 'manager', 'moment', 'anything_else'],
    'Entrega' => ['check_delivery', 'ask_address', 'moment', 'anything_else'],
    'Estoque' => ['check_stock', 'alternatives', 'moment', 'anything_else'],
    _ => ['moment', 'repeat', 'show_item', 'anything_else'],
  };
  return ids.map(findRetailReply).whereType<RetailReply>().toList(growable: false);
}
