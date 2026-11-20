/// A história, contada antes de cada noite. Original: o ateliê, o manequim e
/// a mariposa são deste jogo.
String storyFor(int night) => switch (night) {
  1 =>
    'O Ateliê Valente fechou depois de quarenta anos. No leilão, ninguém quis '
        'o manequim do fundo da loja, o de madeira rachada. Eu paguei dez reais. '
        'Deixei ele no canto do quarto, virado para a parede.',
  2 =>
    'De manhã ele estava virado para a cama. Achei na base dele uma etiqueta '
        'de costura com o meu nome e as minhas medidas, escritas à mão. '
        'Eu nunca entrei naquele ateliê.',
  3 =>
    'A filha do alfaiate respondeu o e-mail. Disse que o pai fazia roupas sob '
        'medida para quem ia desaparecer, e que o manequim tomava as medidas '
        'sozinho, de noite. Pediu para eu não olhar para ele no escuro.',
  4 =>
    'Abri o peito dele com uma chave de fenda. Dentro, entre a palha e o '
        'feltro, havia casulos. Um deles estava aberto. Desde então, alguma '
        'coisa bate as asas sempre que eu acendo a luz.',
  5 =>
    'Os casulos têm etiquetas também. Cada uma com um nome que eu pesquisei: '
        'gente que sumiu de quartos trancados. A minha etiqueta está no último, '
        'ainda fechado.',
  6 =>
    'Ele não quer me matar. Ele quer terminar a roupa. Falta só a medida do '
        'pescoço, e ela se toma de perto.',
  7 =>
    'Esta noite eu queimo o casulo. Se eu chegar até de manhã, acabou. '
        'Se você estiver lendo isto e o seu nome estiver numa etiqueta, não '
        'compre manequins usados.',
  _ =>
    'Noite $night. Os casulos voltaram a crescer. A etiqueta tem uma medida '
        'nova, cada vez mais exata.',
};

/// O que se acha de manhã, depois de sobreviver à noite [night]: vai para o
/// diário. Peças soltas que contam o resto da história.
String foundAfter(int night) => switch (night) {
  1 =>
    'Uma etiqueta de papel pardo, presa no pé dele: "Prova 1 de 7. Cliente '
        'ainda resiste à medida."',
  2 => 'Um alfinete enfiado no batente da porta, na altura do meu pescoço.',
  3 =>
    'Um recibo do Ateliê Valente, de 1987, no nome de alguém que eu não '
        'conheço. Endereço: o meu apartamento.',
  4 =>
    'Asas de mariposa na janela, arrumadas em fila, como amostras de tecido.',
  5 =>
    'Uma fita métrica enrolada no meu travesseiro. Parada em 38 centímetros.',
  6 =>
    'O casulo com o meu nome está mais quente que os outros. Tem alguma coisa '
        'se mexendo dentro.',
  7 =>
    'Cinzas na pia e uma linha preta de costura, que eu não consigo jogar fora.',
  _ => 'Mais uma etiqueta. A letra está mais parecida com a minha.',
};
