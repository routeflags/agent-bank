import React from 'react';

class ChatPanelApp extends React.Component {
  constructor(props) {
    super(props);
    this.state = { isOpen: false };
    this.handleOpen = this.handleOpen.bind(this);
    this.handleClose = this.handleClose.bind(this);
  }

  handleOpen() { this.setState({ isOpen: true }); }
  handleClose() { this.setState({ isOpen: false }); }

  render() {
    var isOpen = this.state.isOpen;
    if (!isOpen) {
      return React.createElement('button', {
        onClick: this.handleOpen,
        className: 'chatPanel__trigger',
        'aria-label': 'Open AI chat',
        type: 'button',
        style: {
          position: 'fixed', bottom: '24px', right: '24px',
          width: '56px', height: '56px', borderRadius: '50%',
          background: '#59b3a2', color: '#fff', border: 'none',
          cursor: 'pointer', boxShadow: '0 4px 12px rgba(0,0,0,0.2)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          zIndex: 999,
        }
      }, '💬');
    }
    return React.createElement('div', {
      style: { position: 'fixed', top: 0, right: 0, width: '400px', height: '100%', background: '#fff', boxShadow: '-2px 0 8px rgba(0,0,0,0.1)', zIndex: 1000, display: 'flex', flexDirection: 'column' }
    },
      React.createElement('div', { style: { padding: '16px', borderBottom: '1px solid #eee', display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
        React.createElement('h3', { style: { margin: 0 } }, this.props.persona_name || 'AI Assistant'),
        React.createElement('button', { onClick: this.handleClose, style: { border: 'none', background: 'none', cursor: 'pointer', fontSize: '20px' } }, '✕')
      ),
      React.createElement('div', { style: { flex: 1, padding: '16px', color: '#999', textAlign: 'center', paddingTop: '40px' } },
        'Start a conversation with ' + (this.props.persona_name || 'the AI assistant') + '.'
      ),
      React.createElement('div', { style: { padding: '16px', borderTop: '1px solid #eee' } },
        React.createElement('input', { type: 'text', placeholder: 'Type a message...', style: { width: '100%', padding: '8px', border: '1px solid #ddd', borderRadius: '4px' } })
      )
    );
  }
}

export default ChatPanelApp;
