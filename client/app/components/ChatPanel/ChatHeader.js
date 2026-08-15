/**
 * ChatHeader — Displays persona name and close button.
 *
 * @param {Object} props
 * @param {string} props.personaName - Name of the AI persona
 * @param {Function} props.onClose - Called when the close button is clicked
 */
import React from 'react';

class ChatHeader extends React.Component {
  render() {
    var personaName = this.props.personaName;

    return (
      React.createElement('div', { className: 'chatPanel__header' },
        React.createElement('h3', { className: 'chatPanel__personaName' },
          personaName || 'AI Assistant'
        ),
        React.createElement('button', {
          className: 'chatPanel__closeBtn',
          onClick: this.props.onClose,
          'aria-label': 'Close chat',
          type: 'button',
        },
          // Simple X icon via SVG
          React.createElement('svg', { width: '20', height: '20', viewBox: '0 0 20 20', fill: 'none', xmlns: 'http://www.w3.org/2000/svg' },
            React.createElement('path', {
              d: 'M15 5L5 15M5 5l10 10',
              stroke: 'currentColor',
              strokeWidth: '2',
              strokeLinecap: 'round',
              strokeLinejoin: 'round',
            })
          )
        )
      )
    );
  }
}

export default ChatHeader;
